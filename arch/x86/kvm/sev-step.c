
#include <linux/sev-step.h>
#include <linux/smp.h>
#include <linux/vmalloc.h>
#include <linux/slab.h>
#include <linux/sched.h>

#include "kvm_cache_regs.h"
#include "svm/svm.h"



struct kvm* main_vm;
EXPORT_SYMBOL(main_vm);

//used to store performance counter values; 6 counters, 2 readings per counter
uint64_t perf_reads[6][2];
perf_ctl_config_t perf_configs[6];
int perf_cpu;


uint64_t perf_ctl_to_u64(perf_ctl_config_t * config) {

	uint64_t result = 0;
	result |= (  config->EventSelect & 0xffULL); //[7:0] in result and  [7:0] in EventSelect
	result |= ( (config->UintMask & 0xffULL) << 8 ); //[15:8]
	result |= ( (config->OsUserMode & 0x3ULL) << 16); //[17:16]
	result |= ( (config->Edge & 0x1ULL ) << 18 ); // 18
	result |= ( (config->Int & 0x1ULL ) << 20 ); // 20
	result |= ( (config->En & 0x1ULL ) << 22 ); //22
	result |= ( (config->Inv & 0x1ULL ) << 23); //23
	result |= ( (config->CntMask & 0xffULL) << 24); //[31:24]
	result |= ( ( (config->EventSelect & 0xf00ULL) >> 8 ) << 32); //[35:32] in result and [11:8] in EventSelect
	result |= ( (config->HostGuestOnly & 0x3ULL) << 40); // [41:40]

	return result;

}

void write_ctl(perf_ctl_config_t * config, int cpu, uint64_t ctl_msr){
	wrmsrl_on_cpu(cpu, ctl_msr, perf_ctl_to_u64(config)); //always returns zero
}

void read_ctr(uint64_t ctr_msr, int cpu, uint64_t* result) {
    uint64_t tmp;
	rdmsrl_on_cpu(cpu, ctr_msr, &tmp); //always returns zero
	*result = tmp & ( (0x1ULL << 48) - 1);
}

void setup_perfs() {
    int i;

    perf_cpu = smp_processor_id();

    for( i = 0; i < 6; i++) {
        perf_configs[i].HostGuestOnly = 0x1; //0x1 means: count only guest
        perf_configs[i].CntMask = 0x0;
        perf_configs[i].Inv = 0x0;
        perf_configs[i].En = 0x0;
        perf_configs[i].Int = 0x0;
        perf_configs[i].Edge = 0x0;
        perf_configs[i].OsUserMode = 0x3; //0x3 means: count userland and kernel events
    }

    //remember to set .En to enable the individual counter

    perf_configs[0].EventSelect = 0x0c0;
	perf_configs[0].UintMask = 0x0;
    perf_configs[0].En = 0x1;
	write_ctl(&perf_configs[0],perf_cpu, CTL_MSR_0);

    /*programm l2d hit from data cache miss perf for
    cpu_probe_pointer_chasing_inplace without counting thread.
    N.B. that this time we count host events
    */
    perf_configs[1].EventSelect = 0x064;
    perf_configs[1].UintMask = 0x70;
    perf_configs[1].En = 0x1;
    perf_configs[1].HostGuestOnly = 0x2; //0x2 means: count only host events, as we do the chase here
    write_ctl(&perf_configs[1],perf_cpu,CTL_MSR_1);
}
EXPORT_SYMBOL(setup_perfs);


/*
static int __my_sev_issue_dbg_cmd(struct kvm *kvm, unsigned long src,
			       unsigned long dst, int size,
			       int *error);

int my_sev_decrypt(struct kvm* kvm, void* dst_vaddr, void* src_vaddr, uint64_t dst_paddr, uint64_t src_paddr, uint64_t len, int* api_res) {

	int call_res;
	call_res  = 0x1337;
	*api_res = 0x1337;


	if( dst_paddr % PAGE_SIZE != 0 || src_paddr % PAGE_SIZE != 0) {
		printk("decrypt: for now, src_paddr, and dst_paddr must be page aligned");
		return -1;
	}

	if( len > PAGE_SIZE ) {
		printk("decrypt: for now, can be at most 4096 byte");
		return -1;
	}

	memset(dst_vaddr,0,PAGE_SIZE);

	//clflush_cache_range(src_vaddr, PAGE_SIZE);
	//clflush_cache_range(dst_vaddr, PAGE_SIZE);
	wbinvd_on_all_cpus();

	call_res = __my_sev_issue_dbg_cmd(kvm, __sme_set(src_paddr),
		__sme_set(dst_paddr), len, api_res);

	return call_res;

}
EXPORT_SYMBOL(my_sev_decrypt);

static int __my_sev_issue_dbg_cmd(struct kvm *kvm, unsigned long src,
			       unsigned long dst, int size,
			       int *error)
{
	struct kvm_sev_info *sev = &to_kvm_svm(kvm)->sev_info;
	struct sev_data_dbg *data;
	int ret;

	data = kzalloc(sizeof(*data), GFP_KERNEL_ACCOUNT);
	if (!data)
		return -ENOMEM;

	data->handle = sev->handle;
	data->dst_addr = dst;
	data->src_addr = src;
	data->len = size;

	//ret = sev_issue_cmd(kvm,
	//		     SEV_CMD_DBG_DECRYPT,
	//		    data, error);
	ret = sev_do_cmd(SEV_CMD_DBG_DECRYPT, data, error);
	kfree(data);
	return ret;
}

int decrypt_vmsa(struct vcpu_svm* svm, struct vmcb_save_area* save_area) {

	uint64_t src_paddr, dst_paddr;
	void * dst_vaddr;
	void * src_vaddr;
	struct page * dst_page;
	int call_res,api_res;
	call_res = 1337;
	api_res = 1337;

	src_vaddr = svm->vmsa;
	src_paddr = svm->vmcb->control.vmsa_pa;

	if( src_paddr % 16 != 0) {
		printk("decrypt_vmsa: src_paddr was not 16b aligned");
	}

	if( sizeof( struct vmcb_save_area) % 16 != 0 ) {
		printk("decrypt_vmsa: size of vmcb_save_area is not 16 b aligned\n");
	}

	dst_page = alloc_page(GFP_KERNEL);
	dst_vaddr =  vmap(&dst_page, 1, 0, PAGE_KERNEL);
	dst_paddr = page_to_pfn(dst_page) << PAGE_SHIFT;
	memset(dst_vaddr,0,PAGE_SIZE);



	if( dst_paddr % 16 != 0 ) {
		printk("decrypt_vmsa: dst_paddr was not 16 byte aligned");
	}

	//printk("src_paddr = 0x%llx dst_paddr = 0x%llx\n", __sme_clr(src_paddr), __sme_clr(dst_paddr));
	//printk("Sizeof vmcb_save_area is: 0x%lx\n", sizeof( struct vmcb_save_area) );


	call_res = __my_sev_issue_dbg_cmd(svm->vcpu.kvm, __sme_set(src_paddr), __sme_set(dst_paddr), sizeof(struct vmcb_save_area), &api_res);


	//printk("decrypt_vmsa: result of call was %d, result of api command was %d\n",call_res, api_res);

	//todo error handling
	if( api_res != 0 ) {
		__free_page(dst_page);
		return -1;
	}

	memcpy(save_area, dst_vaddr, sizeof( struct vmcb_save_area) );


	__free_page(dst_page);

	return 0;


}


//
// Contains a switch to work  SEV and SEV-ES
 //
uint64_t sev_step_get_rip(struct vcpu_svm* svm) {
	struct vmcb_save_area* save_area;
	struct kvm * kvm;
	struct kvm_sev_info *sev;
	uint64_t rip;


	kvm = svm->vcpu.kvm;
	sev = &to_kvm_svm(kvm)->sev_info;

	//for sev-es we need to use the debug api, to decrypt the vmsa
	if( sev->active && sev->es_active) {
		int res;
		save_area = vmalloc(sizeof(struct vmcb_save_area) );
		memset(save_area,0, sizeof(struct vmcb_save_area));

		res = decrypt_vmsa(svm, save_area);
		if( res != 0) {
			printk("sev_step_get_rip failed to decrypt\n");
			return 0;
		}

		rip =  save_area->rip;

		vfree(save_area);
	} else { //otherwise we can just access as plaintexts
		rip = svm->vmcb->save.rip;
	}
	return rip;

}
EXPORT_SYMBOL(sev_step_get_rip);
*/

int sev_step_get_rip_kvm_vcpu(struct kvm_vcpu* vcpu,uint64_t *rip) {
	/*
	struct vcpu_svm *svm = container_of(vcpu, struct vcpu_svm, vcpu);
	if( svm == NULL ) {
		return 1;
	}
	(*rip) = sev_step_get_rip(svm);
	*/
	return 0;
}