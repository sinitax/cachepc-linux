#!/bin/bash

run_cmd()
{
   echo "$*"

   eval "$*" || {
      echo "ERROR: $*"
      exit 1
   }
}


[ -d linux-patches ] && {

	for P in linux-patches/*.patch; do
		run_cmd patch -p1 -d linux < $P
	done
}

MAKE="make -j $(getconf _NPROCESSORS_ONLN) LOCALVERSION="

run_cmd $MAKE distclean

	run_cmd cp /boot/config-$(uname -r) .config
	run_cmd ./scripts/config --set-str LOCALVERSION "-sev-step-snp"
	run_cmd ./scripts/config --disable LOCALVERSION_AUTO
	run_cmd ./scripts/config --disable CONFIG_DEBUG_INFO
#	run_cmd ./scripts/config --undefine CONFIG_SYSTEM_TRUSTED_KEYS
#	run_cmd ./scripts/config --undefine CONFIG_MODULE_SIG_KEY

run_cmd $MAKE olddefconfig

# Build
run_cmd $MAKE >/dev/null

run_cmd $MAKE bindeb-pkg

