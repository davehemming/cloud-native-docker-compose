#!/usr/bin/env bash

declare aws_env_key_file=
declare -r aws_cf_template="`dirname $0`/rancher-env-aws-cf.template"
declare -r aws_cf_stack_name="rancher-stack"
declare -r rs_instance_name="rancher-server"
declare rs_eip=
declare rs_instance_id=
declare rs_instance_state=
declare rs_public_ip=
declare rs_system_status=
declare rs_instance_status=

while getopts "i:k:" opt; do
  case $opt in
    i)
      rs_eip="${OPTARG}"
      ;;
    k)
      aws_env_key_file="${OPTARG}"
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

if [[ ! $aws_env_key_file ]]; then
  echo "aws key file path has not been set. Use the -k option to set it." >&2
  exit 1
elif [[ ! -e $aws_env_key_file ]]; then
  echo "aws key file does not exist" >&2
  exit 1
fi

if [[ ! $rs_eip ]]; then
  echo "aws elastic ip needed for rancher server.  Use the the -i option to set it." >&2
  exit 1
fi

if [[ ! -e $aws_cf_template ]]; then
  echo "the aws cloud formation template file '${aws_cf_template}' does not exist" >&2
  exit 1
fi

aws_stack_exists=$(aws cloudformation describe-stacks \
--stack-name $aws_cf_stack_name \
--output text \
--query 'Stacks[*].StackName' &> /dev/null; echo $?)

if [[ $aws_stack_exists -eq 0 ]]; then
  echo "an aws cloudformation stack with the name '${aws_cf_stack_name}' already exists.\
  Please delete it before rerunning this script." >&2
  exit 1
else
  echo "creating an aws cloudformation stack with the name '${aws_cf_stack_name}'" >&2
  echo -n "..." >&2

  declare -r aws_env_key_file_name=$(basename $aws_env_key_file ".pem")

  aws cloudformation create-stack \
  --stack-name $aws_cf_stack_name \
  --template-body "file://$aws_cf_template" \
  --parameters ParameterKey=KeyName,ParameterValue=$aws_env_key_file_name \
  ParameterKey=EIP,ParameterValue=$rs_eip \
  --capabilities CAPABILITY_NAMED_IAM > /dev/null 2>&1

  aws_cf_stack_creation_status=
  while [[ $aws_cf_stack_creation_status != "CREATE_COMPLETE" ]]; do
    aws_cf_stack_creation_status=$(aws cloudformation describe-stacks \
    --stack-name $aws_cf_stack_name \
    --output text \
    --query 'Stacks[*].StackStatus')

    if [[ $aws_cf_stack_creation_status == "CREATE_COMPLETE" ]]; then
      echo
  	  echo "aws cloudformation stack with the name '${aws_cf_stack_name}' has been created" >&2
    else
      echo -n "." >&2
      sleep 1
    fi
  done

fi

echo "waiting for rancher server to come up" >&2
echo -n "..."
while [[ $rs_instance_state != "running" ]]; do
  read rs_instance_id rs_instance_state rs_public_ip <<< \
    $(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=$rs_instance_name" \
    "Name=instance-state-name,Values=pending,running,shutting-down,stopping,stopped" \
    --output text --query "Reservations[*].Instances[*].[InstanceId, State.Name, PublicIpAddress]")

  if [[ $rs_instance_state == "running" ]]; then
  	echo
  	echo "rancher server is up" >&2
  else
  	echo -n "." >&2
  	sleep 1
  fi

done

echo "waiting for rancher server to pass status checks" >&2
echo -n "..."
while [[ $rs_system_status != "ok" ||  $rs_instance_status != "ok" ]]; do
  read rs_system_status rs_instance_status <<< \
    $(aws ec2 describe-instance-status \
    --instance-ids $rs_instance_id \
    --output text --query "InstanceStatuses[*].[SystemStatus.Status, InstanceStatus.Status]")

  if [[ $rs_system_status == "ok" && $rs_instance_status == "ok" ]]; then
  	echo
  	echo "rancher server has passed status checks" >&2
  else
  	echo -n "." >&2
  	sleep 1
  fi

done

# remove public key certificate if it exists to prevent ssh error
ssh-keygen -R $rs_public_ip > /dev/null 2>&1

rs_docker_installed=0
echo "waiting for docker to finish installing" >&2
echo -n "..."
while [[ $rs_docker_installed -ne 1 ]]; do
  rs_docker_installed=$(ssh -o "StrictHostKeyChecking no" \
  -i $aws_env_key_file ubuntu@$rs_public_ip \
   "command -v docker &> /dev/null && echo 1 || echo 0" 2>/dev/null)

  if [[ $rs_docker_installed -eq 1 ]]; then
  	echo
  	echo "docker has finished installing" >&2
  else
  	echo -n "." >&2
  	sleep 1
  fi
done

## check if a reboot is required due to system upgrades that were applied during initial system provisioning
rs_reboot_required=$(ssh -o "StrictHostKeyChecking no" \
-i $aws_env_key_file ubuntu@$rs_public_ip \
"if [[ -f /var/run/reboot-required ]]; then echo 1; else echo 0; fi" 2>/dev/null)

if [[ $rs_reboot_required -eq 1 ]]; then
  echo "rebooting system to apply updates. This may take a while.";
  echo -n "..."
  aws ec2 stop-instances --instance-ids $rs_instance_id > /dev/null 2>&1

  rs_insstance_state=
  while [[ $rs_instance_state != "stopped" ]]; do
    read rs_instance_id rs_instance_state rs_public_ip <<< \
      $(aws ec2 describe-instances \
      --filters "Name=tag:Name,Values=$rs_instance_name" \
      "Name=instance-state-name,Values=pending,running,shutting-down,stopping,stopped" \
      --output text --query "Reservations[*].Instances[*].[InstanceId, State.Name, PublicIpAddress]")

    if [[ $rs_instance_state != "stopped" ]]; then
      echo -n "." >&2
      sleep 1
    fi
  done

  aws ec2 start-instances --instance-ids $rs_instance_id > /dev/null 2>&1
  rs_insstance_state=
  while [[ $rs_instance_state != "running" ]]; do
    read rs_instance_id rs_instance_state rs_public_ip <<< \
      $(aws ec2 describe-instances \
      --filters "Name=tag:Name,Values=$rs_instance_name" \
      "Name=instance-state-name,Values=pending,running,shutting-down,stopping,stopped" \
      --output text --query "Reservations[*].Instances[*].[InstanceId, State.Name, PublicIpAddress]")

    if [[ $rs_instance_state != "running" ]]; then
      echo -n "." >&2
      sleep 1
    fi
  done

  rs_system_status=
  rs_instance_status=
  while [[ $rs_system_status != "ok" ||  $rs_instance_status != "ok" ]]; do
    read rs_system_status rs_instance_status <<< \
      $(aws ec2 describe-instance-status \
      --instance-ids $rs_instance_id \
      --output text --query "InstanceStatuses[*].[SystemStatus.Status, InstanceStatus.Status]")

    if [[ $rs_system_status != "ok" && $rs_instance_status != "ok" ]]; then
    	echo -n "." >&2
    	sleep 1
    fi
  done

  rc_server_ssh_open=1
  while [[ $rc_server_ssh_open -ne 0 ]]; do

    rc_server_ssh_open=$(nc -w 1 $rs_public_ip 22 &> /dev/null; echo $?)
    if [[ $rc_server_ssh_open -eq 0 ]]; then
      echo
      echo "rancher server is back up after reboot"
    else
      echo -n "." >&2
    fi
  done
fi

echo "starting the rancher server docker image"
ssh -o "StrictHostKeyChecking no" \
-i $aws_env_key_file ubuntu@$rs_public_ip \
"sudo docker run -d --restart=unless-stopped -p 8080:8080 rancher/server" 2>/dev/null

echo "waiting for the rancher server docker image to start running"
echo -n "..."
declare rs_docker_container_running=
while [[ $rs_docker_container_running -ne 200 ]]; do
  rs_docker_container_running=$(curl -s -o /dev/null -w "%{http_code}" http://13.55.223.157:8080/)

  if [[ $rs_docker_container_running -eq 200 ]]; then
  	echo
  	echo "the rancher server docker image has started running" >&2
  else
  	echo -n "." >&2
  	sleep 1
  fi
done

exit 0
