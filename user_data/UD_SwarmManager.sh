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
        # Waits 10 seconds - in order to minize chance of collision (several nodes created at the same time by ASG, some claiming to be the first ones)
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


#Get manager token tag from instance id
function GetManagerToken()
{

        ManagerToken=$(aws ec2 describe-tags --output text  --region $region --filters Name=resource-id,Values=${1} Name=key,Values=ManagerToken | cut -f5)
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
        echo ${DomainName}

        aws route53 change-resource-record-sets --hosted-zone-id ${HostedZoneId} --change-batch '{"Changes": [{"Action": "UPSERT","ResourceRecordSet": {"Name": "'"${MyHostName}.${DomainName}"'","Type": "A","TTL": 60,"ResourceRecords": [{"Value": "'"${MyInstanceIP}"'"}]}}]}'

}

function SetCurrInstName()
{
        #Determine this nodes name, use the lowest free index (i.e if swarmmanager1 was terminated, the next node created by
        #the autoscaling group will be named SwarmManager1, and so on)
        InitNodeName=$(echo "${arrManagerNodes[0]}" | awk -F ';' '{print $2}')
        MinNameIndex=${InitNodeName: -1}
        MaxNameIndex=$MinNameIndex

        for nd in "${arrManagerNodes[@]}"
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

        # If min index is greater then one we will name the node minindex - 1 - i.e if the lowest named node is SwarmManager2
        # the following node created by autoscaling will be named SwarmManager1. Otherwise, if the lowest is SwarmManager1
        # the following one will be named SwarmManager2
        if [[ $MinNameIndex > 1  ]]; then
                myNameIndex=$(expr $MinNameIndex - 1)
        else
                myNameIndex=$(expr $MaxNameIndex + 1)
        fi

        myName="SwarmManager${myNameIndex}"
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

arrNodesLength=${#arrManagerNodes[@]}

# If no other nodes wait a random period of time to avoid collision
if [[ $arrNodesLength < 1 ]]
then

        sleep  $[ ( $RANDOM % 10 )  + 20 ]s
        GetManagers
        arrNodesLength=${#arrManagerNodes[@]}
fi

# If there are no other manager nodes, the cluster will be initiated by this node and it will be given the name SwarmManager1
if [[ $arrNodesLength <  1 ]]
then
        # Set identifying tags (PartOf and InstanceRole)

        SetTagOnInstance "PartOf" "FinalProject"
        SetTagOnInstance "InstanceRole" "SwarmManager"

        echo "No other manager nodes exist, will set this node as the first SwarmManager node"

        # Set Name tag
        SetTagOnInstance "Name" "SwarmManager1"

        sudo ocker swarm leave --force
        sudo docker swarm init --advertise-addr $MyInstanceIP
        ManagerToken=$(sudo docker swarm join-token manager -q)
        WorkerToken=$(sudo docker swarm join-token worker -q)
        SetTagOnInstance "ManagerToken" $ManagerToken
        SetTagOnInstance "WorkerToken" $WorkerToken
# If other nodes exist we have to:
# 1. Determine how to name the current node
# 2. Join an existing cluster as an additional manager
else
        SetCurrInstName

        for ndCurr in "${arrManagerNodes[@]}"
        do
                ndInstId=$(echo $ndCurr | awk -F ';' '{print $1}')
                ndInstIp=$(echo $ndCurr | awk -F ';' '{print $3}')
                GetManagerToken "$ndInstId"


                if [[ ! -z  $ManagerToken ]]; then
                {
                        echo ${ndInstIp}:2377
                        # Join swarm
                        sudo docker swarm join --token $ManagerToken ${ndInstIp}:2377

                        ManagerToken=$(sudo docker swarm join-token manager -q)
                        WorkerToken=$(sudo docker swarm join-token worker -q)

                        # Set identifying tags (PartOf and InstanceRole)
                        SetTagOnInstance "PartOf" "FinalProject"
                        SetTagOnInstance "InstanceRole" "SwarmManager"
                        SetTagOnInstance "ManagerToken" $ManagerToken
                        SetTagOnInstance "WorkerToken" $WorkerToken
                        break
                }
                fi
        done
fi

UpdateDNS
