#include "textflag.h"

TEXT libc_dlopen_trampoline<>(SB),NOSPLIT,$0-0
	JMP	libc_dlopen(SB)
GLOBL	·libc_dlopen_trampoline_addr(SB), RODATA, $8
DATA	·libc_dlopen_trampoline_addr(SB)/8, $libc_dlopen_trampoline<>(SB)

TEXT libc_dlsym_trampoline<>(SB),NOSPLIT,$0-0
	JMP	libc_dlsym(SB)
GLOBL	·libc_dlsym_trampoline_addr(SB), RODATA, $8
DATA	·libc_dlsym_trampoline_addr(SB)/8, $libc_dlsym_trampoline<>(SB)
