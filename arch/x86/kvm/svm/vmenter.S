/* SPDX-License-Identifier: GPL-2.0 */
#include <linux/linkage.h>
#include <asm/asm.h>
#include <asm/bitsperlong.h>
#include <asm/kvm_vcpu_regs.h>
#include <asm/nospec-branch.h>

#define WORD_SIZE (BITS_PER_LONG / 8)

/* Intentionally omit RAX as it's context switched by hardware */
#define VCPU_RCX	__VCPU_REGS_RCX * WORD_SIZE
#define VCPU_RDX	__VCPU_REGS_RDX * WORD_SIZE
#define VCPU_RBX	__VCPU_REGS_RBX * WORD_SIZE
/* Intentionally omit RSP as it's context switched by hardware */
#define VCPU_RBP	__VCPU_REGS_RBP * WORD_SIZE
#define VCPU_RSI	__VCPU_REGS_RSI * WORD_SIZE
#define VCPU_RDI	__VCPU_REGS_RDI * WORD_SIZE

#ifdef CONFIG_X86_64
#define VCPU_R8		__VCPU_REGS_R8  * WORD_SIZE
#define VCPU_R9		__VCPU_REGS_R9  * WORD_SIZE
#define VCPU_R10	__VCPU_REGS_R10 * WORD_SIZE
#define VCPU_R11	__VCPU_REGS_R11 * WORD_SIZE
#define VCPU_R12	__VCPU_REGS_R12 * WORD_SIZE
#define VCPU_R13	__VCPU_REGS_R13 * WORD_SIZE
#define VCPU_R14	__VCPU_REGS_R14 * WORD_SIZE
#define VCPU_R15	__VCPU_REGS_R15 * WORD_SIZE
#endif

.section .noinstr.text, "ax"

.extern cachepc_msrmts
.extern cachepc_regs_tmp
.extern cachepc_regs_vm

.macro load_tmp off reg
	mov cachepc_regs_tmp+\off(%rip), \reg
.endm

.macro save_tmp off reg
	mov \reg, cachepc_regs_tmp+\off(%rip)
.endm

.macro load_vm off reg
	mov cachepc_regs_vm+\off(%rip), \reg
.endm

.macro save_vm off reg
	mov \reg, cachepc_regs_vm+\off(%rip)
.endm

.macro apply_regs func
	\func 0x00, %rax
	\func 0x08, %rbx
	\func 0x10, %rcx
	\func 0x18, %rdx
	\func 0x20, %rbp
	\func 0x28, %rsp
	\func 0x30, %rdi
	\func 0x38, %rsi
	\func 0x40, %r8
	\func 0x48, %r9
	\func 0x50, %r10
	\func 0x58, %r11
	\func 0x60, %r12
	\func 0x68, %r13
	\func 0x70, %r14
	\func 0x78, %r15
.endm

/**
 * __svm_vcpu_run - Run a vCPU via a transition to SVM guest mode
 * @vmcb_pa:	unsigned long
 * @regs:	unsigned long * (to guest registers)
 */
SYM_FUNC_START(__svm_vcpu_run)
	apply_regs save_tmp

	push %_ASM_BP
#ifdef CONFIG_X86_64
	push %r15
	push %r14
	push %r13
	push %r12
#else
	push %edi
	push %esi
#endif
	push %_ASM_BX

	/* Save @regs. */
	push %_ASM_ARG2

	/* Save @vmcb. */
	push %_ASM_ARG1

	/* Move @regs to RAX. */
	mov %_ASM_ARG2, %_ASM_AX

	/* Load guest registers. */
	mov VCPU_RCX(%_ASM_AX), %_ASM_CX
	mov VCPU_RDX(%_ASM_AX), %_ASM_DX
	mov VCPU_RBX(%_ASM_AX), %_ASM_BX
	mov VCPU_RBP(%_ASM_AX), %_ASM_BP
	mov VCPU_RSI(%_ASM_AX), %_ASM_SI
	mov VCPU_RDI(%_ASM_AX), %_ASM_DI
#ifdef CONFIG_X86_64
	mov VCPU_R8 (%_ASM_AX),  %r8
	mov VCPU_R9 (%_ASM_AX),  %r9
	mov VCPU_R10(%_ASM_AX), %r10
	mov VCPU_R11(%_ASM_AX), %r11
	mov VCPU_R12(%_ASM_AX), %r12
	mov VCPU_R13(%_ASM_AX), %r13
	mov VCPU_R14(%_ASM_AX), %r14
	mov VCPU_R15(%_ASM_AX), %r15
#endif

	/* "POP" @vmcb to RAX. */
	pop %_ASM_AX

	/* Enter guest mode */
	sti

1:	
	apply_regs save_vm
	apply_regs load_tmp
	mov cachepc_ds, %rsi
	mov 0x8(%rsi), %r15
	lea sev_prime_ret(%rip), %rdi
	jmp cachepc_prime_vcall+5+1 // skip stack pushs
sev_prime_ret:
	apply_regs save_tmp
	apply_regs load_vm

	vmrun %_ASM_AX

	apply_regs save_vm
	apply_regs load_tmp
	mov %r15, %rsi
	lea sev_probe_ret(%rip), %rdi
	jmp cachepc_probe_vcall+5+8 // skip stack pushs
sev_probe_ret:
	apply_regs save_tmp
	apply_regs load_vm

2:	cli

#ifdef CONFIG_RETPOLINE
	/* IMPORTANT: Stuff the RSB immediately after VM-Exit, before RET! */
	FILL_RETURN_BUFFER %_ASM_AX, RSB_CLEAR_LOOPS, X86_FEATURE_RETPOLINE
#endif

	/* "POP" @regs to RAX. */
	pop %_ASM_AX

	/* Save all guest registers.  */
	mov %_ASM_CX,   VCPU_RCX(%_ASM_AX)
	mov %_ASM_DX,   VCPU_RDX(%_ASM_AX)
	mov %_ASM_BX,   VCPU_RBX(%_ASM_AX)
	mov %_ASM_BP,   VCPU_RBP(%_ASM_AX)
	mov %_ASM_SI,   VCPU_RSI(%_ASM_AX)
	mov %_ASM_DI,   VCPU_RDI(%_ASM_AX)
#ifdef CONFIG_X86_64
	mov %r8,  VCPU_R8 (%_ASM_AX)
	mov %r9,  VCPU_R9 (%_ASM_AX)
	mov %r10, VCPU_R10(%_ASM_AX)
	mov %r11, VCPU_R11(%_ASM_AX)
	mov %r12, VCPU_R12(%_ASM_AX)
	mov %r13, VCPU_R13(%_ASM_AX)
	mov %r14, VCPU_R14(%_ASM_AX)
	mov %r15, VCPU_R15(%_ASM_AX)
#endif

	/*
	 * Clear all general purpose registers except RSP and RAX to prevent
	 * speculative use of the guest's values, even those that are reloaded
	 * via the stack.  In theory, an L1 cache miss when restoring registers
	 * could lead to speculative execution with the guest's values.
	 * Zeroing XORs are dirt cheap, i.e. the extra paranoia is essentially
	 * free.  RSP and RAX are exempt as they are restored by hardware
	 * during VM-Exit.
	 */
	xor %ecx, %ecx
	xor %edx, %edx
	xor %ebx, %ebx
	xor %ebp, %ebp
	xor %esi, %esi
	xor %edi, %edi
#ifdef CONFIG_X86_64
	xor %r8d,  %r8d
	xor %r9d,  %r9d
	xor %r10d, %r10d
	xor %r11d, %r11d
	xor %r12d, %r12d
	xor %r13d, %r13d
	xor %r14d, %r14d
	xor %r15d, %r15d
#endif

	pop %_ASM_BX

#ifdef CONFIG_X86_64
	pop %r12
	pop %r13
	pop %r14
	pop %r15
#else
	pop %esi
	pop %edi
#endif
	pop %_ASM_BP
	RET

3:	cmpb $0, kvm_rebooting
	jne 2b
	ud2

	_ASM_EXTABLE(1b, 3b)

SYM_FUNC_END(__svm_vcpu_run)

/**
 * __svm_sev_es_vcpu_run - Run a SEV-ES vCPU via a transition to SVM guest mode
 * @vmcb_pa:	unsigned long
 */
SYM_FUNC_START(__svm_sev_es_vcpu_run)
	apply_regs save_tmp

	push %_ASM_BP
#ifdef CONFIG_X86_64
	push %r15
	push %r14
	push %r13
	push %r12
#else
	push %edi
	push %esi
#endif
	push %_ASM_BX

	/* Move @vmcb to RAX. */
	mov %_ASM_ARG1, %_ASM_AX

	/* Enter guest mode */
	sti

1:	

	apply_regs save_vm
	apply_regs load_tmp
	mov cachepc_ds, %rsi
	mov 0x8(%rsi), %r15
	lea sev_es_prime_ret(%rip), %rdi
	jmp cachepc_prime_vcall+5+1 // skip stack pushes
sev_es_prime_ret:
	apply_regs save_tmp
	apply_regs load_vm

	vmrun %_ASM_AX

	apply_regs save_vm
	apply_regs load_tmp
	mov %r15, %rsi
	lea sev_es_probe_ret(%rip), %rdi
	jmp cachepc_probe_vcall+5+8 // skip stack pushs
sev_es_probe_ret:
	apply_regs save_tmp
	apply_regs load_vm

2:	cli

#ifdef CONFIG_RETPOLINE
	/* IMPORTANT: Stuff the RSB immediately after VM-Exit, before RET! */
	FILL_RETURN_BUFFER %_ASM_AX, RSB_CLEAR_LOOPS, X86_FEATURE_RETPOLINE
#endif

	pop %_ASM_BX

#ifdef CONFIG_X86_64
	pop %r12
	pop %r13
	pop %r14
	pop %r15
#else
	pop %esi
	pop %edi
#endif
	pop %_ASM_BP
	RET

3:	cmpb $0, kvm_rebooting
	jne 2b
	ud2

	_ASM_EXTABLE(1b, 3b)

SYM_FUNC_END(__svm_sev_es_vcpu_run)
