/* Isolated OS-entropy failure injection against the actual pinned provider. */
#include <tomcrypt.h>
#include <stdio.h>
#if defined(_WIN32)
#include <windows.h>
#include <wincrypt.h>
#undef CryptAcquireContext
#define CryptAcquireContext(...) 0
#else
#define fopen(...) ((FILE*)0)
#endif
#include "rng_get_bytes.c"
int main(void) {
  unsigned char output[32] = {0};
  if (rng_get_bytes(output, sizeof output, NULL) != 0) return 1;
  puts("{\"os_rng_failure_returns_zero\":true,\"clock_rng_fallback\":false}");
  return 0;
}
