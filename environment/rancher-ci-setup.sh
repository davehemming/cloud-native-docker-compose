#!/usr/bin/env bash

declare -r ci_env_name=Jenkins
declare -r aws_driver=amazonec2
declare -r aws_region=ap-southeast-2
declare aws_access_key=
declare aws_secret_key=
declare aws_zone=a
declare aws_rs_vpc_id=$(aws ec2 describe-vpcs --filters \
declare 'Name=tag:Name,Values=rancher-vpc' --output text --query 'Vpcs[*].VpcId')
declare aws_rs_subnet_id=$(aws ec2 describe-subnets --filters \
declare 'Name=tag:Name,Values=rancher-subnet-public' --output text --query 'Subnets[*].SubnetId')
declare aws_rs_security_group_name=$(aws ec2 describe-security-groups --filters \
declare 'Name=tag:Name,Values=rancher-security-group' --output text \
declare --query 'SecurityGroups[*].GroupName')
declare -r host_name=host-02
declare -r docker_install_url=https://releases.rancher.com/install-docker/1.11.sh

while getopts "a:s:" opt; do
  case $opt in
    a)
      aws_access_key="${OPTARG}"
      ;;
    s)
      aws_secret_key="${OPTARG}"
      ;;
    \?)
      echo "invalid option: -${OPTARG}" >&2
      exit 1
      ;;
    :)
      echo "option -${OPTARG} requires an argument" >&2
      exit 1
      ;;
  esac
done

# TODO: Check if rancher server is up and running first

jenkins_ci_env_id=$(rancher env ls | grep $ci_env_name | awk '{print $1;}')
if [[ -z $jenkins_ci_env_id ]]; then
  echo "creating Jenkins environment" >&2
  rancher env create -t kubernetes $ci_env_name > /dev/null

  while [[ -z $jenkins_ci_env_id ]]; do
    jenkins_ci_env_id=$(rancher env ls | grep $ci_env_name | awk '{print $1;}')
    sleep 1
  done
fi

# TODO: Display error messages from failed host provisioning to the terminal (immediate errors and delayed errors)
echo "provisioning Jenkins host server" >&2
echo -n "..." >&2
$(rancher --env $jenkins_ci_env_id hosts create --driver $aws_driver  \
--amazonec2-region $aws_region --amazonec2-access-key $aws_access_key \
--amazonec2-secret-key $aws_secret_key --amazonec2-zone $aws_zone \
--amazonec2-vpc-id $aws_rs_vpc_id \
--amazonec2-subnet-id $aws_rs_subnet_id \
--amazonec2-security-group $aws_rs_security_group_name --name $host_name \
--engine-install-url $docker_install_url)

#echo "rancher --env $jenkins_ci_env_id hosts create --driver $aws_driver  \
#--amazonec2-region $aws_region --amazonec2-access-key $aws_access_key \
#--amazonec2-secret-key $aws_secret_key --amazonec2-zone $aws_zone \
#--amazonec2-vpc-id $aws_rs_vpc_id \
#--amazonec2-subnet-id $aws_rs_subnet_id \
#--amazonec2-security-group $aws_rs_security_group_name --name $host_name \
#--amazonec2-device-name $host_name \
#--engine-install-url $docker_install_url

#if [[ $? -eq 0 ]]; then
#  host_id=
#  host_status=
#  while [[ $host_status != "active" ]]; do
#    read host_id host_status <<< $(rancher hosts | grep $rancher_host_id | awk '{print $1 "\t" $3}')
#
#    if [[ $host_status == "active" ]]; then
#      echo
#      echo "Jenkins host has been successfully created" >&2
#    elif [[ $host_status == "error" ]]; then
#      echo
#      echo "failed to create Jenkins host, an error occurred" >&2
#      exit 1
#    else
#      echo -n "." >&2
#      sleep 1
#    fi
#  done
#
#else
#  echo
#  echo "creation of Jenkins host failed" >&2
#  exit 1
#fi

exit 0
