// mozc-ffi: the C API in mozc_ffi.h, over Mozc's ConverterInterface.

#include "mozc_ffi/mozc_ffi.h"

#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <memory>
#include <mutex>
#include <string>
#include <system_error>
#include <unordered_set>
#include <utility>
#include <vector>

#include "absl/strings/string_view.h"
#include "absl/types/span.h"
#include "base/system_util.h"
#include "base/util.h"
#include "base/version.h"
#include "config/config_handler.h"
#include "converter/converter_interface.h"
#include "converter/segments.h"
#include "data_manager/oss/oss_data_manager.h"
#include "engine/engine.h"
#include "protocol/commands.pb.h"
#include "protocol/config.pb.h"
#include "request/conversion_request.h"

struct mozc_ffi {
  std::mutex mutex;
  std::unique_ptr<mozc::Engine> engine;
  std::shared_ptr<const mozc::ConverterInterface> converter;
  mozc::config::Config config;
  mozc::commands::Request request;
  bool incognito = false;
};

struct mozc_ffi_result {
  struct Segment {
    std::string reading;
    std::vector<std::string> candidates;
  };
  std::vector<Segment> segments;
};

namespace {

using mozc::ConversionRequest;

// What mozc_ffi_last_error returns: always a string literal, so it needs no
// cleanup and can never hold what was typed.
thread_local const char* last_error = "";

template <typename T>
T Fail(const char* why, T value) {
  last_error = why;
  return value;
}

constexpr char kNoHandle[] = "the mozc handle is NULL";
constexpr char kNoReading[] = "the reading is empty";
constexpr char kNotSaved[] = "Mozc could not write the profile";

absl::string_view View(const char* text) {
  return text == nullptr ? absl::string_view() : absl::string_view(text);
}

ConversionRequest MakeRequest(const mozc_ffi& mozc,
                              ConversionRequest::RequestType type,
                              absl::string_view key,
                              const mozc::commands::Context& context) {
  ConversionRequest::Options options;
  options.request_type = type;
  options.incognito_mode = mozc.incognito;
  // We pass the reading as the key, never a composer. Without this,
  // dictionary predictions read the (empty) composer and complete nothing.
  options.use_already_typing_corrected_key = true;
  mozc::ConversionRequestBuilder builder;
  builder.SetRequestView(mozc.request)
      .SetContextView(context)
      .SetConfigView(mozc.config)
      .SetOptions(std::move(options));
  if (!key.empty()) {
    builder.SetKey(key);
  }
  return builder.Build();
}

// The text before the reading becomes Mozc's history, as when typing on.
mozc::commands::Context MakeContext(const mozc_ffi& mozc,
                                    absl::string_view preceding,
                                    mozc::Segments* segments) {
  mozc::commands::Context context;
  if (!preceding.empty()) {
    context.set_preceding_text(preceding);
    // Without a history Mozc converts as at the start of a sentence.
    (void)mozc.converter->ReconstructHistory(segments, preceding);
  }
  return context;
}

// Converts `reading`, then cuts it into `lengths` when given. Returns why it
// failed, or nullptr.
const char* Convert(const mozc_ffi& mozc, absl::string_view reading,
                    absl::Span<const int32_t> lengths,
                    absl::string_view preceding, mozc::Segments* segments) {
  std::vector<uint8_t> sizes;
  if (!lengths.empty()) {
    size_t total = 0;
    for (const int32_t length : lengths) {
      if (length <= 0 || length > 255) {
        return "a segment length is not between 1 and 255";
      }
      total += length;
      sizes.push_back(static_cast<uint8_t>(length));
    }
    if (total != mozc::Util::CharsLen(reading)) {
      return "the segment lengths do not add up to the reading's length";
    }
  }
  const mozc::commands::Context context =
      MakeContext(mozc, preceding, segments);
  const ConversionRequest request =
      MakeRequest(mozc, ConversionRequest::CONVERSION, reading, context);
  if (!mozc.converter->StartConversion(request, segments)) {
    return "Mozc could not convert the reading";
  }
  if (sizes.empty()) {
    return nullptr;
  }
  constexpr char kNotCut[] =
      "Mozc could not cut the reading into those segment lengths";
  if (!mozc.converter->ResizeSegments(segments, request, 0, sizes) ||
      segments->conversion_segments_size() != sizes.size()) {
    return kNotCut;
  }
  for (size_t i = 0; i < sizes.size(); ++i) {
    if (segments->conversion_segment(i).key_len() != sizes[i]) {
      return kNotCut;
    }
  }
  return nullptr;
}

mozc_ffi_result* MakeResult(const mozc::Segments& segments) {
  auto result = std::make_unique<mozc_ffi_result>();
  for (size_t i = 0; i < segments.conversion_segments_size(); ++i) {
    const mozc::Segment& segment = segments.conversion_segment(i);
    mozc_ffi_result::Segment out;
    out.reading = std::string(segment.key());
    // Mozc can hold one text twice (as different words); show it once, as
    // Mozc's own candidate window does. learn() commits the first of them.
    std::unordered_set<std::string> seen;
    for (int j = 0; j < static_cast<int>(segment.candidates_size()); ++j) {
      const std::string& value = segment.candidate(j).value;
      if (seen.insert(value).second) {
        out.candidates.push_back(value);
      }
    }
    result->segments.push_back(std::move(out));
  }
  return result.release();
}

const mozc_ffi_result::Segment* GetSegment(const mozc_ffi_result* result,
                                           int32_t segment) {
  if (result == nullptr || segment < 0 ||
      static_cast<size_t>(segment) >= result->segments.size()) {
    return nullptr;
  }
  return &result->segments[segment];
}

}  // namespace

extern "C" {

int32_t mozc_ffi_abi_version(void) { return MOZC_FFI_ABI_VERSION; }

const char* mozc_ffi_mozc_version(void) {
  static const std::string* version =
      new std::string(mozc::Version::GetMozcVersion());
  return version->c_str();
}

const char* mozc_ffi_last_error(void) { return last_error; }

mozc_ffi* mozc_ffi_open(const char* profile_dir, int32_t flags) {
  last_error = "";
  if (profile_dir != nullptr && *profile_dir != '\0') {
    std::error_code error;
    const std::filesystem::path path(
        std::u8string(reinterpret_cast<const char8_t*>(profile_dir)));
    std::filesystem::create_directories(path, error);
    if (error) {
      return Fail<mozc_ffi*>("the profile directory could not be created",
                             nullptr);
    }
    mozc::SystemUtil::SetUserProfileDirectory(profile_dir);
  }
  auto engine =
      mozc::Engine::CreateEngine(std::make_unique<mozc::oss::OssDataManager>());
  if (!engine.ok()) {
    return Fail<mozc_ffi*>("Mozc's engine could not start", nullptr);
  }
  auto mozc = std::make_unique<mozc_ffi>();
  mozc->engine = std::move(engine).value();
  mozc->converter = mozc->engine->GetConverter();
  mozc->incognito = (flags & MOZC_FFI_INCOGNITO) != 0;
  mozc->config = mozc::config::ConfigHandler::DefaultConfig();
  mozc->config.set_incognito_mode(mozc->incognito);
  return mozc.release();
}

void mozc_ffi_close(mozc_ffi* mozc) {
  if (mozc == nullptr) {
    return;
  }
  if (!mozc->incognito) {
    mozc->engine->Sync();
    mozc->engine->Wait();
  }
  delete mozc;
}

mozc_ffi_result* mozc_ffi_convert(mozc_ffi* mozc, const char* reading,
                                  const int32_t* lengths, int32_t n_lengths,
                                  const char* context) {
  last_error = "";
  if (mozc == nullptr) {
    return Fail<mozc_ffi_result*>(kNoHandle, nullptr);
  }
  if (View(reading).empty()) {
    return Fail<mozc_ffi_result*>(kNoReading, nullptr);
  }
  if (n_lengths < 0 || (n_lengths > 0 && lengths == nullptr)) {
    return Fail<mozc_ffi_result*>("lengths is NULL or its count is negative",
                                  nullptr);
  }
  std::lock_guard<std::mutex> lock(mozc->mutex);
  mozc::Segments segments;
  if (const char* why =
          Convert(*mozc, reading, absl::MakeConstSpan(lengths, n_lengths),
                  View(context), &segments)) {
    return Fail<mozc_ffi_result*>(why, nullptr);
  }
  return MakeResult(segments);
}

mozc_ffi_result* mozc_ffi_predict(mozc_ffi* mozc, const char* reading,
                                  const char* context) {
  last_error = "";
  if (mozc == nullptr) {
    return Fail<mozc_ffi_result*>(kNoHandle, nullptr);
  }
  if (View(reading).empty()) {
    return Fail<mozc_ffi_result*>(kNoReading, nullptr);
  }
  std::lock_guard<std::mutex> lock(mozc->mutex);
  mozc::Segments segments;
  const mozc::commands::Context preceding =
      MakeContext(*mozc, View(context), &segments);
  const ConversionRequest request =
      MakeRequest(*mozc, ConversionRequest::PREDICTION, reading, preceding);
  if (!mozc->converter->StartPrediction(request, &segments)) {
    return new mozc_ffi_result();  // Nothing to predict is not an error.
  }
  return MakeResult(segments);
}

int32_t mozc_ffi_segment_count(const mozc_ffi_result* result) {
  return result == nullptr ? 0 : static_cast<int32_t>(result->segments.size());
}

const char* mozc_ffi_segment_reading(const mozc_ffi_result* result,
                                     int32_t segment) {
  const mozc_ffi_result::Segment* found = GetSegment(result, segment);
  return found == nullptr ? nullptr : found->reading.c_str();
}

int32_t mozc_ffi_candidate_count(const mozc_ffi_result* result,
                                 int32_t segment) {
  const mozc_ffi_result::Segment* found = GetSegment(result, segment);
  return found == nullptr ? 0 : static_cast<int32_t>(found->candidates.size());
}

const char* mozc_ffi_candidate(const mozc_ffi_result* result, int32_t segment,
                               int32_t index) {
  const mozc_ffi_result::Segment* found = GetSegment(result, segment);
  if (found == nullptr || index < 0 ||
      static_cast<size_t>(index) >= found->candidates.size()) {
    return nullptr;
  }
  return found->candidates[index].c_str();
}

void mozc_ffi_result_free(mozc_ffi_result* result) { delete result; }

int32_t mozc_ffi_learn(mozc_ffi* mozc, const char* reading,
                       const int32_t* lengths, const char* const* texts,
                       int32_t n, const char* context) {
  last_error = "";
  if (mozc == nullptr) {
    return Fail(kNoHandle, 0);
  }
  if (View(reading).empty()) {
    return Fail(kNoReading, 0);
  }
  if (n <= 0 || lengths == nullptr || texts == nullptr) {
    return Fail("lengths or texts is NULL, or there are no segments", 0);
  }
  std::lock_guard<std::mutex> lock(mozc->mutex);
  mozc::Segments segments;
  if (const char* why = Convert(*mozc, reading, absl::MakeConstSpan(lengths, n),
                                View(context), &segments)) {
    return Fail(why, 0);
  }
  // Find every pick before committing any, so a mismatch learns nothing.
  std::vector<int> picks;
  for (int32_t i = 0; i < n; ++i) {
    if (texts[i] == nullptr) {
      return Fail("a text is NULL", 0);
    }
    const mozc::Segment& segment = segments.conversion_segment(i);
    int pick = -1;
    for (int j = 0; j < static_cast<int>(segment.candidates_size()); ++j) {
      if (segment.candidate(j).value == texts[i]) {
        pick = j;
        break;
      }
    }
    if (pick < 0) {
      return Fail("a text is not a candidate of its segment", 0);
    }
    picks.push_back(pick);
  }
  for (int32_t i = 0; i < n; ++i) {
    if (!mozc->converter->CommitSegmentValue(&segments, i, picks[i])) {
      return Fail("Mozc could not commit a candidate", 0);
    }
  }
  mozc::commands::Context preceding;
  if (context != nullptr) {
    preceding.set_preceding_text(context);
  }
  mozc->converter->FinishConversion(
      MakeRequest(*mozc, ConversionRequest::CONVERSION, reading, preceding),
      &segments);
  return 1;
}

int32_t mozc_ffi_clear_learning(mozc_ffi* mozc) {
  last_error = "";
  if (mozc == nullptr) {
    return Fail(kNoHandle, 0);
  }
  std::lock_guard<std::mutex> lock(mozc->mutex);
  if (!mozc->engine->ClearUserHistory() ||
      !mozc->engine->ClearUserPrediction()) {
    return Fail("Mozc could not clear what it learned", 0);
  }
  return mozc->engine->Sync() && mozc->engine->Wait() ? 1 : Fail(kNotSaved, 0);
}

int32_t mozc_ffi_flush(mozc_ffi* mozc) {
  last_error = "";
  if (mozc == nullptr) {
    return Fail(kNoHandle, 0);
  }
  std::lock_guard<std::mutex> lock(mozc->mutex);
  return mozc->engine->Sync() && mozc->engine->Wait() ? 1 : Fail(kNotSaved, 0);
}

}  // extern "C"
