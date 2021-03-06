#!/bin/bash
AvailabilityZone=$(ec2-metadata --availability-zone | cut -d ' ' -f2)
region=${AvailabilityZone%?}
MyInstanceID=$(ec2-metadata -i | cut -d ' ' -f2)
MyInstanceIP=$(ec2-metadata -o | cut -d ' ' -f2)

echo $MyInstanceIP

# Sets tag on current instance, First argument is the name of the tag and the second is it's value
function SetTagOnInstance()
{
        aws --region $region  ec2 create-tags --resources $MyInstanceID --tags Key=${1},Value=${2}
}

# Get Other managers by instancerole tag and partof tag. returns array of nodes
function GetManagers()
{
        ManagerNodes=$(aws \
                       --output text --region $region ec2 describe-instances \
                       --filters Name=tag-key,Values=PartOf Name=tag-value,Values=FinalProject \
                                 Name=tag-key,Values=InstanceRole Name=tag-value,Values=SwarmManager \
                                 Name=instance-state-name,Values=running \
                       --query 'Reservations[*].Instances[*].{A:InstanceId,B:Tags[?Key==`Name`]|[0].Value,C:PrivateIpAddress}')

        arrManagerNodes=()

        #Read output, each line represents a node
        while read -r line; do
                node=$(echo $line | tr ' ' ';')

                #Exclude self

                if [[ $node != *"$MyInstanceID"* ]]; then
                {
                        arrManagerNodes+=( $node )
                }
                fi

        done <<< "$ManagerNodes"
}


function GetWorkers()
{
        sleep  $[ ($RANDOM) % 100 ]s

        WorkerNodes=$(aws \
                       --output text --region $region ec2 describe-instances \
                       --filters Name=tag-key,Values=PartOf Name=tag-value,Values=FinalProject \
                                 Name=tag-key,Values=InstanceRole Name=tag-value,Values=SwarmWorker \
                                 Name=instance-state-name,Values=running \
                       --query 'Reservations[*].Instances[*].{A:InstanceId,B:Tags[?Key==`Name`]|[0].Value,C:PrivateIpAddress}')

        arrWorkerNodes=()

        #Read output, each line represents a node
        while read -r line; do
                node=$(echo $line | tr ' ' ';')

                #Exclude self

                if [[ $node != *"$MyInstanceID"* ]]; then
                {
                        arrWorkerNodes+=( $node )
                }
                fi

        done <<< "$WorkerNodes"
}


#Get manager token tag from instance id
function GetManagerToken()
{

        ManagerToken=$(aws ec2 describe-tags --output text  --region $region --filters Name=resource-id,Values=${1} Name=key,Values=ManagerToken | cut -f5)
}

function GetWorkerToken()
{

        WorkerToken=$(aws ec2 describe-tags --output text  --region $region --filters Name=resource-id,Values=${1} Name=key,Values=WorkerToken | cut -f5)
}

function GetOwnTag()
{
        TagVal=$(aws ec2 describe-tags --output text  --region $region --filters Name=resource-id,Values=${MyInstanceID} Name=key,Values=${1} | cut -f5)
}

function GetHostedZoneID()
{
        GetOwnTag "DomainName"
        DomainName=${TagVal}
        HostedZoneId=$(aws route53 list-hosted-zones-by-name --dns-name ${DomainName} --query HostedZones[].Id --output text | cut -d/ -f3)
}

function UpdateDNS()
{
        echo 'Updating DNS'
        GetHostedZoneID
        GetOwnTag "Name"
        MyHostName=${TagVal}

        aws route53 change-resource-record-sets --hosted-zone-id ${HostedZoneId} --change-batch '{"Changes": [{"Action": "UPSERT","ResourceRecordSet": {"Name": "'"${MyHostName}.${DomainName}"'","Type": "A","TTL": 60,"ResourceRecords": [{"Value": "'"${MyInstanceIP}"'"}]}}]}'

}

function SetCurrInstName()
{
        #Determine this nodes name, use the lowest free index (i.e if swarmmanager1 was terminated, the next node created by
        #the autoscaling group will be named SwarmManager1, and so on)
        InitNodeName=$(echo "${arrWorkerNodes[0]}" | awk -F ';' '{print $2}')
        MinNameIndex=${InitNodeName: -1}
        MaxNameIndex=$MinNameIndex

        for nd in "${arrWorkerNodes[@]}"
        do
                ndName=$(echo $nd | awk -F ';' '{print $2}')
                ndIndex=${ndName: -1}

                if [[ $ndIndex < $MinNameIndex ]];
                then
                        MinNameIndex=$ndIndex
                elif [[ $ndIndex > $MaxNameIndex ]];
                then
                       MaxNameIndex=$ndIndex
                fi
        done

        # If min index is greater then one we will name the node minindex - 1 - i.e if the lowest named node is SwarmWorker2
        # the following node created by autoscaling will be named SwarmWorker1. Otherwise, if the lowest is SwarmWorker1
        # the following one will be named SwarmManager2
        if [[ $MinNameIndex > 1  ]]; then
                myNameIndex=$(expr $MinNameIndex - 1)
        else
                myNameIndex=$(expr $MaxNameIndex + 1)
        fi

        myName="SwarmWorker${myNameIndex}"
        echo "Setting name tag to $myName"
        SetTagOnInstance "Name" $myName
}

function InstallDocker()
{
        sudo yum install -y docker
        sudo systemctl enable docker
        sudo usermod -a -G docker ec2-user
        sudo systemctl start docker
}


InstallDocker
GetManagers

arrManNodesLength=${#arrManagerNodes[@]}

# If no managers exist the script will wait maximum of 600 seconds
WaitTimeout=600
TimeWaited=0
WaitSecs=30

echo $TimeWaited

while [[ $arrManNodesLength  -lt 1 && $TimeWaited -lt $WaitTimeout   ]]
do
        echo "No managers available yet, waiting ${WaitSecs} seconds. ${TimeWaited} waited so far"
        sleep ${WaitSecs}s
        TimeWaited=$(expr ${TimeWaited} + ${WaitSecs}) 
        GetManagers
        arrManNodesLength=${#arrManagerNodes[@]}
done

if [[ $arrManNodesLength < 1 ]]
then
        echo "ERROR: No manager nodes after ${WaitTimeout} seconds, Exitting with error"
        exit 1
else
        GetWorkers
        SetCurrInstName

        for nd in "${arrManagerNodes[@]}"
        do

                manID=$(echo $nd | awk -F ';' '{print $1}')
                manIP=$(echo $nd | awk -F ';' '{print $3}')

                GetWorkerToken $manID
                sudo docker swarm join --token $WorkerToken ${manIP}:2377
        done
fi

SetTagOnInstance "PartOf" "FinalProject"
SetTagOnInstance "InstanceRole" "SwarmWorker"
UpdateDNS
