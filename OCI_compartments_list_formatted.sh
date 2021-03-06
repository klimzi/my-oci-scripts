#!/bin/bash

# --------------------------------------------------------------------------------------------------------------
# This script will list the compartment names and IDs in a OCI tenant using OCI CLI
# It will also list all subcompartments
# The output will be formatted with colors and indents to easily identify parents of subcompartments
#
# Note: OCI tenant given by an OCI CLI PROFILE
# Author        : Christophe Pauliat
# Last update   : May 24, 2019
# Platforms     : MacOS / Linux
# prerequisites : OCI CLI installed and OCI config file configured with profiles
# --------------------------------------------------------------------------------------------------------------

usage()
{
cat << EOF
Usage: $0 OCI_PROFILE

note: OCI_PROFILE must exist in ~/.oci/config file (see example below)

[EMEAOSCf]
tenancy     = ocid1.tenancy.oc1..aaaaaaaaw7e6nkszrry6d5hxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
user        = ocid1.user.oc1..aaaaaaaayblfepjieoxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
fingerprint = 19:1d:7b:3a:17:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx
key_file    = /Users/cpauliat/.oci/api_key.pem
region      = eu-frankfurt-1
EOF
  exit 1
}

get_cpt_name_from_id()
{
  id=$1
  grep -A 2 $id $TMP_FILE|egrep -v "ocid1.compartment|ACTIVE|DELETED"
}

get_cpt_state_from_id()
{
  id=$1
  grep -A 2 $id $TMP_FILE|egrep  "ACTIVE|DELETED"
}

# $1 = parent compartment
list_compartments()
{
  local parent_id=$1
  local level=$2    # 0 for root, 1 for 1st level compartments, ...
  local i
  local nb_cpts

  i=1;
  while [ $i -le `expr $level - 1` ]
  do
    if [ `cat tmp_last_$i` == "0" ]; then printf "${COLOR_CYAN}│      "; else printf "       "; fi
    ((i++))
  done
  if [ $level -gt 0 ]; then
    if [ `cat tmp_last_$level` == "0" ]; then printf "${COLOR_CYAN}├───── "; else printf "${COLOR_CYAN}└───── "; fi
  fi

  if [ $level -gt 0 ]; then
    cptname=`get_cpt_name_from_id $parent_id`
    state=`get_cpt_state_from_id $parent_id`
  else
    cptname='root'
    state="ACTIVE"
  fi
  if [ "$state" == "ACTIVE" ]; then
    printf "${COLOR_GREEN}%s ${COLOR_DEFAULT}%s ${COLOR_YELLOW}ACTIVE \n" "$cptname" "$parent_id"
  else
    printf "${COLOR_BLUE}%s ${COLOR_GREY}%s ${COLOR_RED}DELETED \n" "$cptname" "$parent_id"
  fi

  cptid_list=`oci --profile $PROFILE iam compartment list -c $parent_id --all| grep "^ *\"id" |awk -F'"' '{ print $4 }'`
  if [ "$cptid_list" != "" ]; then
    nb_cpts=`echo $cptid_list | wc -w`
    i=1
    for cptid in $cptid_list
    do
      level1=`expr $level + 1`
      if [ $i -eq $nb_cpts ]; then echo 1 > tmp_last_$level1; else echo 0 > tmp_last_$level1; fi
      list_compartments $cptid `expr $level + 1`
      ((i++))
    done
  fi
}

# -------- main

OCI_CONFIG_FILE=~/.oci/config
TMP_FILE=tmp_all_cpts_$$

if [ $# -ne 1 ]; then usage; fi

PROFILE=$1

COLOR_YELLOW="\e[93m"
COLOR_RED="\e[91m"
COLOR_GREEN="\e[32m"
COLOR_DEFAULT="\e[39m"
COLOR_CYAN="\e[96m"
COLOR_BLUE="\e[94m"
COLOR_GREY="\e[90m"

# -- Check if the PROFILE exists
grep "\[$PROFILE\]" $OCI_CONFIG_FILE > /dev/null 2>&1
if [ $? -ne 0 ]; then echo "ERROR: PROFILE $PROFILE does not exist in file $OCI_CONFIG_FILE !"; exit 2; fi

# -- get tenancy OCID from OCI PROFILE
TENANCYOCID=`egrep "^\[|ocid1.tenancy" $OCI_CONFIG_FILE|sed -n -e "/\[$PROFILE\]/,/tenancy/p"|tail -1| awk -F'=' '{ print $2 }' | sed 's/ //g'`

# -- get the list of all compartments and sub-compartments (excluding root compartment)
oci --profile $PROFILE iam compartment list -c $TENANCYOCID --compartment-id-in-subtree true --all 2>/dev/null| egrep "^ *\"name|^ *\"id|^ *\"lifecycle-state"|awk -F'"' '{ print $4 }' >$TMP_FILE

# -- recursive call to list all compartments and sub-compartments in right order
list_compartments $TENANCYOCID 0 false

rm -f $TMP_FILE tmp_last_*
