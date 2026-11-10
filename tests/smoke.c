/* A C program that links against the library and converts one reading, built
 * as strict C99 so the header stays plain C.
 *
 *   smoke <profile-dir>
 */
#include <stdio.h>
#include <string.h>

#include "mozc_ffi.h"

/* きょうは, as UTF-8 bytes so every compiler reads it the same way. */
static const char kReading[] =
    "\xe3\x81\x8d\xe3\x82\x87\xe3\x81\x86\xe3\x81\xaf";

int main(int argc, char** argv) {
  mozc_ffi* mozc;
  mozc_ffi_result* result;
  const char* first;
  int ok;

  if (mozc_ffi_abi_version() != MOZC_FFI_ABI_VERSION) {
    fputs("the library speaks another ABI version\n", stderr);
    return 1;
  }
  mozc = mozc_ffi_open(argc > 1 ? argv[1] : NULL, MOZC_FFI_INCOGNITO);
  if (mozc == NULL) {
    fprintf(stderr, "mozc_ffi_open failed: %s\n", mozc_ffi_last_error());
    return 1;
  }
  /* A failure says why, and the next success clears it. */
  result = mozc_ffi_convert(mozc, "", NULL, 0, NULL);
  if (result != NULL || mozc_ffi_last_error()[0] == '\0') {
    fputs("an empty reading gave no error\n", stderr);
    return 1;
  }
  result = mozc_ffi_convert(mozc, kReading, NULL, 0, NULL);
  first = mozc_ffi_candidate(result, 0, 0);
  ok = result != NULL && mozc_ffi_last_error()[0] == '\0' &&
       mozc_ffi_segment_count(result) >= 1 &&
       strcmp(mozc_ffi_segment_reading(result, 0), kReading) == 0 &&
       first != NULL && first[0] != '\0';
  printf("Mozc %s: %d segment(s), %s\n", mozc_ffi_mozc_version(),
         mozc_ffi_segment_count(result), ok ? "ok" : "FAILED");
  mozc_ffi_result_free(result);
  mozc_ffi_close(mozc);
  return ok ? 0 : 1;
}
