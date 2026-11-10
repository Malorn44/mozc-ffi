/* mozc-ffi: a C API over Mozc's kana-kanji converter, in process.
 *
 * Every call is self-contained: it carries the reading (and, optionally, the
 * segment lengths and the text before it), so callers keep no state in sync
 * with the library. All strings are UTF-8. Segment lengths count Unicode
 * characters, not bytes.
 *
 * One handle may be used from several threads; calls on it are serialized.
 * Mozc keeps the profile directory per process, so open one profile per
 * process. Readings and learning data are the user's typing: this library
 * never logs them. */
#ifndef MOZC_FFI_H_
#define MOZC_FFI_H_

#include <stdint.h>

#if defined(_WIN32)
#if defined(MOZC_FFI_BUILD)
#define MOZC_FFI_API __declspec(dllexport)
#else
#define MOZC_FFI_API __declspec(dllimport)
#endif
#else
#define MOZC_FFI_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* Bumped whenever the functions below change. Wrappers check it on load. */
#define MOZC_FFI_ABI_VERSION 2
MOZC_FFI_API int32_t mozc_ffi_abi_version(void);

/* Why the last mozc_ffi_open, convert, predict, learn, clear_learning or
 * flush on this thread failed, in English, or "" if it succeeded. A fixed
 * string that never holds what was typed; valid for the life of the
 * process. */
MOZC_FFI_API const char* mozc_ffi_last_error(void);

/* Mozc's version, such as "2.32.5994.102". */
MOZC_FFI_API const char* mozc_ffi_mozc_version(void);

typedef struct mozc_ffi mozc_ffi;
typedef struct mozc_ffi_result mozc_ffi_result;

/* Learn nothing and leave the profile untouched. */
#define MOZC_FFI_INCOGNITO 1

/* profile_dir holds what Mozc learns; it is created if missing. NULL or ""
 * uses Mozc's default (~/.mozc on Linux). The dictionary is built in.
 * Returns NULL on failure (see mozc_ffi_last_error). */
MOZC_FFI_API mozc_ffi* mozc_ffi_open(const char* profile_dir, int32_t flags);
/* Saves what was learned and frees the handle. */
MOZC_FFI_API void mozc_ffi_close(mozc_ffi* mozc);

/* Converts a reading (hiragana) into segments with candidates, best first.
 * lengths (optional, n_lengths entries summing to the reading's length) fix
 * the segment boundaries; NULL lets Mozc choose them. context (optional) is
 * the text just before the reading, which helps the first segment.
 * Returns NULL on failure or invalid lengths. */
MOZC_FFI_API mozc_ffi_result* mozc_ffi_convert(mozc_ffi* mozc,
                                               const char* reading,
                                               const int32_t* lengths,
                                               int32_t n_lengths,
                                               const char* context);

/* Completions for a reading typed so far, as one segment of candidates. */
MOZC_FFI_API mozc_ffi_result* mozc_ffi_predict(mozc_ffi* mozc,
                                               const char* reading,
                                               const char* context);

/* Reading a result. Strings stay valid until mozc_ffi_result_free. */
MOZC_FFI_API int32_t mozc_ffi_segment_count(const mozc_ffi_result* result);
MOZC_FFI_API const char* mozc_ffi_segment_reading(const mozc_ffi_result* result,
                                                  int32_t segment);
MOZC_FFI_API int32_t mozc_ffi_candidate_count(const mozc_ffi_result* result,
                                              int32_t segment);
MOZC_FFI_API const char* mozc_ffi_candidate(const mozc_ffi_result* result,
                                            int32_t segment, int32_t index);
MOZC_FFI_API void mozc_ffi_result_free(mozc_ffi_result* result);

/* Learns a conversion the user sent: the reading cut into n segments of
 * `lengths`, with texts[i] picked for segment i, so those picks rank first
 * next time. Returns 1 if every text was a candidate of its segment and the
 * conversion was learned, else 0 (nothing is learned). */
MOZC_FFI_API int32_t mozc_ffi_learn(mozc_ffi* mozc, const char* reading,
                                    const int32_t* lengths,
                                    const char* const* texts, int32_t n,
                                    const char* context);

/* Forgets everything learned. Returns 1 on success. */
MOZC_FFI_API int32_t mozc_ffi_clear_learning(mozc_ffi* mozc);
/* Writes what was learned to the profile. Returns 1 on success. */
MOZC_FFI_API int32_t mozc_ffi_flush(mozc_ffi* mozc);

#ifdef __cplusplus
}
#endif

#endif /* MOZC_FFI_H_ */
