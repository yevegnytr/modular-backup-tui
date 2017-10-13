#!/bin/bash
# Modular backup-resrore script
# libncurses based TUI using dialog
# Parallel compression with pbzip2 and progress gauge with pv
# Written by Yevgeny Trachtinov (jendoz@gmail.com)

# Global variables
# ==================================
# File date format
FDATE=`date +"%H-%M-%S_%d-%m-%Y"`
# Log file format
LOGFILE=$BACKUP_LOCATION/backup_$FDATE.log
# How many logs to rotate
LOGROTATE=10
# How many backups to rotate
BKP_ROTATE=7
# From where to read content to be compressed with tar
CONF_FILE=backup.conf
# ==================================

# Check if the host is AIPP enabled (encryption/decryption of backup archive)
if [ -d /export/home/fpd/GPG ];then
		AIPP="true"
	else
		AIPP="false"
fi

# Check if PV is installed
echo "Checking if pv is installed..."
dpkg-query -l | grep pv > /dev/null
if [ $? -eq 0 ];
  then
    echo "PV is installed"
  else
    echo "PV is not installed. Installing"
    dpkg -i pv*
fi

# Check if pbzip2 is installed
echo "Checking if pbzip2 is installed..."
dpkg-query -l | grep pbzip2 > /dev/null
if [ $? -eq 0 ];
  then
    echo "pbzip2 is installed"
  else
    echo "pbzip2 is not installed. Installing"
    dpkg -i pbzip2*
fi



# Functions used in steps
# =======================

# readme
readme() {
  whiptail --title "Instructions" --textbox readme.txt 30 60 --scrolltext
}

# Log files rotation
log_rotate() {
  LOG_FILECOUNT=`ls -1 | grep log | wc -l`
   if [ $LOG_FILECOUNT -gt ${LOGROTATE} ]; then
      echo "$(date +"%Y/%m/%d %H:%M:%S") More than ${LOGROTATE} log files found. Rotating logs." >> $LOGFILE
      ls -1 *.log | head -n -${LOGROTATE} | xargs rm > /dev/null 2>&1
    else
      echo "$(date +"%Y/%m/%d %H:%M:%S") Less than ${LOGROTATE} log files found. Not rotating logs." >> $LOGFILE
   fi
}



# Backup files rotation
backup_rotate() {
	if [ $AIPP = "true" ]; then
		BACKUP_COUNT=`ls -1 ${BACKUP_LOCATION}*.gpg | wc -l`
			if [ $BACKUP_COUNT -gt ${BKP_ROTATE}  ]; then
				echo "$(date +"%Y/%m/%d %H:%M:%S") More than ${BKP_ROTATE} encrypted backup files found. Rotating." >> $LOGFILE
				ls -1 ${BACKUP_LOCATION}*.gpg | head -n -${BKP_ROTATE} | xargs rm > /dev/null 2>&1
			else
				echo "$(date +"%Y/%m/%d %H:%M:%S") Backup files are less than ${BKP_ROTATE} found. Not rotating." >> $LOGFILE
			fi
		
		else
			BACKUP_COUNT=`ls -1 ${BACKUP_LOCATION}*.tar.bz2 | wc -l`
			if [ $BACKUP_COUNT -gt ${BKP_ROTATE}  ]; then
				echo "$(date +"%Y/%m/%d %H:%M:%S") More than ${BKP_ROTATE} backup not-encrypted files found. Rotating." >> $LOGFILE
				ls -1 ${BACKUP_LOCATION}*.gpg | head -n -${BKP_ROTATE} | xargs rm > /dev/null 2>&1
			else
				echo "$(date +"%Y/%m/%d %H:%M:%S") Backup files are less than ${BKP_ROTATE} found. Not rotating." >> $LOGFILE
			fi
	fi
}

# Decrypt (and extract) backup file
decrypt_file() {
	echo "$(date +"%Y/%m/%d %H:%M:%S") AIPP status is $AIPP." >> $LOGFILE
	if [ $AIPP = "true" ]; then
			echo "$(date +"%Y/%m/%d %H:%M:%S") Starting decryption..." >> $LOGFILE
			export GNUPGHOME=/export/home/fpd/.gnupg
			tpm_unsealdata -z -i /export/home/fpd/.gnupg/gpg_pass_QtmDevMch | gpg2  -o /export/restore.tar.bz2 --yes --batch  --passphrase-fd 0 $RESTORE_FILE >> $LOGFILE
			time tar xvf /export/restore.tar.bz2 -C / >> $LOGFILE
			rm -f /export/restore.tar.bz2
		else
			echo "$(date +"%Y/%m/%d %H:%M:%S") Copying not encrypted file to local storage before extract." >> $LOGFILE
			rsync -v --log-file-format="%t - %f %b" --log-file=$LOGFILE --progress $RESTORE_FILE /export/
			time tar xvf /export/QTM*.tar.bz2 -C / >> $LOGFILE
			rm -f /export/QTM*.tar.bz2
	fi
}


# Directoy select (used in backup location)
select_backup_dir() {
BACKUP_LOCATION=`dialog --stdout --title "Please choose backup location." --dselect / 20 35`

  case $? in
    0)
      echo "$(date +"%Y/%m/%d %H:%M:%S") $BACKUP_LOCATION was chosen as backup location." >> $LOGFILE;;
    1)
      echo "$(date +"%Y/%m/%d %H:%M:%S") Cancel pressed." >> $LOGFILE
      exit 1;;
    255)
      echo "$(date +"%Y/%m/%d %H:%M:%S") Box closed." >> $LOGFILE;;
  esac
}


# Yes/No select
yesno() {
  if (whiptail --title "Quantum backup/restore" --yesno "Are you sre that you want to start?" 8 40) then
    echo "$(date +"%Y/%m/%d %H:%M:%S") User selected 'Yes' on confirmation." >> $LOGFILE
  else
    echo "$(date +"%Y/%m/%d %H:%M:%S") User selected 'No' on confirmation." >> $LOGFILE
    exit 1
  fi
}


# Compress list from conf file with progress bar
compress_files() {
  echo "$(date +"%Y/%m/%d %H:%M:%S") Staring compression from backup list." >> $LOGFILE
  (tar cf - --files-from $CONF_FILE \
    | pv -n -s $(find $(cat backup.conf | tr '\r\n' ' ') -type f -exec du -sb {} \;| awk '{print $1}' | awk '{ sum += $0 } END { print sum }') \
    | pbzip2 -vrc -9 > QTM_backup_${HOSTNAME}_$FDATE.tar.bz2) 2>&1 \
    | dialog --gauge 'Compressing files' 7 70
}


# Rsync the file after we checked that we have enough free space on destination
copy_backup_file() {
  echo "$(date +"%Y/%m/%d %H:%M:%S") Staring to copy backup file to destination..." >> $LOGFILE
  rsync -v --remove-source-files --log-file-format="%t - %f %b" --log-file=$LOGFILE --progress QTM_backup_${HOSTNAME}_$FDATE.tar.bz2* ${BACKUP_LOCATION}
}  


# Encrypt compressed archive using machine gpg keys
encrypt_arch() {
  echo "$(date +"%Y/%m/%d %H:%M:%S") AIPP status is $AIPP." >> $LOGFILE
	if [ $AIPP = "true" ]; then
		echo "$(date +"%Y/%m/%d %H:%M:%S") Staring encryption of backup archive." >> $LOGFILE
		export GNUPGHOME=/export/home/fpd/.gnupg
		gpg2 -e -r QtmDevMch --yes --always-trust --batch "QTM_backup_${HOSTNAME}_$FDATE.tar.bz2" >> $LOGFILE
			if [ $? -eq 0 ]
				then
					echo "$(date +"%Y/%m/%d %H:%M:%S") Ecryption done." >> $LOGFILE
					rm -f "QTM_backup_${HOSTNAME}_$FDATE.tar.bz2"
				else
					echo "$(date +"%Y/%m/%d %H:%M:%S") Encryption failed." >> $LOGFILE
					rm -f "QTM_backup_${HOSTNAME}_$FDATE.tar.bz2"
					exit 1
			fi
	else
		echo "$(date +"%Y/%m/%d %H:%M:%S") No need/Could not encrypt archive." >> $LOGFILE
	fi
}


# Get operator name
operator_name () {
OP_NAME=$(whiptail --inputbox "Please enter your name" 8 78 --title "Script operator name" 3>&1 1>&2 2>&3)
exitstatus=$?
	if [ $exitstatus = 0 ]; then
		echo "$(date +"%Y/%m/%d %H:%M:%S") User selected Ok and entered \"$OP_NAME\" as operator name." >> $LOGFILE
	else
		echo "$(date +"%Y/%m/%d %H:%M:%S") User selected Cancel." >> $LOGFILE
		exit 1
	fi
}

# Get restore location (not used)
restore-location() {
RESTORE_LOCATION=$(whiptail --inputbox "Where do you want to backup the computer?" 8 68 --title "Backup location select" 3>&1 1>&2 2>&3)
exitstatus=$?
	if [ $exitstatus = 0 ]; then
		echo "$(date +"%Y/%m/%d %H:%M:%S") User selected Ok and entered $RESTORE_LOCATION" >> $LOGFILE
	else
		echo "$(date +"%Y/%m/%d %H:%M:%S") User selected Cancel." >> $LOGFILE
		exit 1
	fi
}


# Check size before backup
check_size() {
DST_FREE_SPACE=`df ${BACKUP_LOCATION} | awk 'FNR == 2 {print $4}'`
BACKUP_FILE_SIZE=`du QTM_backup_${HOSTNAME}_$FDATE.tar.bz2* | awk '{print $1}'`

	if [ "$DST_FREE_SPACE" -gt "$BACKUP_FILE_SIZE" ];
		then
			echo "$(date +"%Y/%m/%d %H:%M:%S") There is enough space on destination." >> $LOGFILE
		else
			echo "$(date +"%Y/%m/%d %H:%M:%S") There is NOT enough space in destination." >> $LOGFILE
			dialog --colors --backtitle "Free space check"  --title "Error!" --msgbox '\ZbNot enough free space on destination.\Zn' 6 45
			rm -f QTM_backup_${HOSTNAME}_$FDATE.tar.bz2*
			exit 1
  fi
}


# ***start of restore sequence***
# File select for restore
select_restore_file() {
RESTORE_FILE=`dialog --stdout --title "Please choose backup file to restore." --fselect / 20 100`

  case $? in
    0)
      echo "$(date +"%Y/%m/%d %H:%M:%S") $RESTORE_FILE was chosen as restore file." >> $LOGFILE;;
    1)
      echo "$(date +"%Y/%m/%d %H:%M:%S") Cancel pressed." >> $LOGFILE
      exit 1;;
    255)
      echo "$(date +"%Y/%m/%d %H:%M:%S") Box closed." >> $LOGFILE;;
  esac
# Going to next sequence
yesno
operator_name
decrypt_file
log_rotate
}


# ***Start of backup sequence***
# Display content of backup configuration file and proceed to next steps
show_conf_file() {
  whiptail --title "Content of the conf file. Scroll with arrow keys. Tab to jump to OK." --textbox backup.conf 30 80 --scrolltext
# Go to next steps
  yesno
  echo "$(date +"%Y/%m/%d %H:%M:%S") Staring backup script." >> $LOGFILE
  echo "$(date +"%Y/%m/%d %H:%M:%S") The content of the config file was:" >> $LOGFILE
  cat $CONF_FILE >> $LOGFILE
  echo ""  >> $LOGFILE
  select_backup_dir
  operator_name
  compress_files
  encrypt_arch
  check_size
  copy_backup_file
  log_rotate
  backup_rotate
}

# ===========================================================================================



# Welcome screen
whiptail --title "Quantum AIPP enabled backup/restore" --msgbox "Welcome to backup/restore script! Press any key to continue." 8 48
# README
readme

# Select if the user want to backup/restore/exit
CHOICE=$(
whiptail --title "Operation" --menu "Please choose your desired operation" 16 68 5 \
  "1)" "Backup" 3>&2 2>&1 1>&3 \
  "2)" "Restore" 3>&2 2>&1 1>&3 \
  "3)" "Exit" 3>&2 2>&1 1>&3
)
case $CHOICE in
  "1)") show_conf_file ;;
  "2)") select_restore_file ;;
  "3)") exit 1
esac
