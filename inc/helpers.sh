#!/bin/bash

exit_with_error()
{
    echo $1
    exit 1
}
grab_version()
{
	local ver=()
	ver[0]=$(grep "^VERSION" "${1}"/Makefile | head -1 | awk '{print $(NF)}' | grep -oE '^[[:digit:]]+')
	ver[1]=$(grep "^PATCHLEVEL" "${1}"/Makefile | head -1 | awk '{print $(NF)}' | grep -oE '^[[:digit:]]+')
	ver[2]=$(grep "^SUBLEVEL" "${1}"/Makefile | head -1 | awk '{print $(NF)}' | grep -oE '^[[:digit:]]+')
	ver[3]=$(grep "^EXTRAVERSION" "${1}"/Makefile | head -1 | awk '{print $(NF)}' | grep -oE '^-rc[[:digit:]]+')
	echo "${ver[0]:-0}${ver[1]:+.${ver[1]}}${ver[2]:+.${ver[2]}}${ver[3]}"
}

display_yesno() {
  exec 3>&1
  dialog --title "$1" \
    --no-collapse \
    --yesno "$2" $DIALOG_HEIGHT $DIALOG_WIDTH
  exit_status=$?
  exec 3>&-
  case $exit_status in
    $DIALOG_CANCEL)
      selection='off'
      ;;
    $DIALOG_OK)
      selection='on'
      ;;
  esac
}

display_result() {
  dialog --title "$1" \
    --no-collapse \
    --msgbox "$2" $DIALOG_HEIGHT $DIALOG_WIDTH
}

display_select() {
  exec 3>&1
  selection=$(dialog \
    --backtitle "$BACKTITLE" \
    --title "$1" \
    --clear \
    --cancel-label "Exit" \
    --menu "$2" $DIALOG_HEIGHT $DIALOG_WIDTH 0 \
    "${@:3}" \
    2>&1 1>&3)
  exit_status=$?
  exec 3>&-
  case $exit_status in
    $DIALOG_CANCEL)
      echo "Program terminated."
      exit
      ;;
    $DIALOG_ESC)
      echo "Program aborted." >&2
      exit 1
      ;;
  esac
}

display_input() {
  exec 3>&1
  selection=$(dialog \
    --backtitle "$BACKTITLE" \
    --title "$1" \
    --clear \
    --cancel-label "Exit" \
    --inputbox "$2" $DIALOG_HEIGHT $DIALOG_WIDTH "$3" \
    2>&1 1>&3)
  exit_status=$?
  exec 3>&-
  case $exit_status in
    $DIALOG_CANCEL)
      echo "Program terminated."
      exit
      ;;
    $DIALOG_ESC)
      echo "Program aborted." >&2
      exit 1
      ;;
  esac
}

display_checklist() {
  exec 3>&1
  selection=$(dialog \
    --backtitle "$BACKTITLE" \
    --title "$1" \
    --clear \
    --cancel-label "Exit" \
    --checklist "$2" $DIALOG_HEIGHT $DIALOG_WIDTH 0 \
    "${@:3}" \
    2>&1 1>&3)
  exit_status=$?
  exec 3>&-

  case $exit_status in
    $DIALOG_CANCEL)
      echo "Program terminated."
      exit
      ;;
    $DIALOG_ESC)
      echo "Program aborted." >&2
      exit 1
      ;;
  esac
}

read_arguments() {
    # read command line to replace defaults
    POSITIONAL=()
    while [[ $# -gt 0 ]]
    do
        key="$1"
        value="$2"

        case $key in
            # feature selection
            --kernel)
                BUILD_KERNEL='on'
                shift;
            ;;
            --clean)
                CLEAN_KERNEL_SRC='on'
                shift;
            ;;
            --config)
                ALLOW_KERNEL_CONFIG_CHANGES='on'
                shift;
            ;;


            --rootfs)
                BUILD_ROOTFS='on'
                shift;
            ;;
            --changes)
                ALLOW_ROOTFS_CHANGES='on'
                shift;
            ;;
            --initramfs)
	            BUILD_INITRAMFS='on'
	            shift;
            ;;
            --cmdline)
                ALLOW_CMDLINE_CHANGES='on'
                shift;
            ;;


            --ghrunner)
                GHRUNNER='on'
                THREADS=2
                shift;
            ;;


            #  config selection

            --release)
                release=${value}
                shift; shift
            ;;
            --root-pw)
                root_pw=${value}
                shift; shift
            ;;
            --hostname)
                def_hostname=${value}
                shift; shift;
            ;;
            --kernelbranch)
                kernel_branch=${value}
                shift; shift;
            ;;
            --zram)
                ZRAM_ENABLED='on'
                shift;
            ;;

            --boot)
                BOOT_DEVICE=${value}
                shift; shift;
            ;;

            *)    # unknown option
                POSITIONAL+=("$1") # save it in an array for later
                shift # past argument
            ;;
        esac
    done
}
