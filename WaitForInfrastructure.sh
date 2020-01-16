#!/bin/bash
AvailabilityZone=$(ec2-metadata --availability-zone | cut -d ' ' -f2)
region=${AvailabilityZone%?}

function GetProjectNodes()
{
    AllProjectNodes=$(aws \
                      --output text --region $region ec2 describe-instances \
                      --filters Name=tag-key,Values=PartOf Name=tag-value,Values=FinalProject \
                        Name=instance-state-name,Values=running,pending \
                      --query 'Reservations[*].Instances[*].{A:InstanceId}')
}

function GetProjectPendingNodes()
{
    AllPendingNodes=$(aws \
                      --output text --region $region ec2 describe-instances \
                      --filters Name=tag-key,Values=PartOf Name=tag-value,Values=FinalProject \
                                Name=instance-state-name,Values=pending \
                      --query 'Reservations[*].Instances[*].{A:InstanceId}')
}

function GetInitializingNodes()
{
    InitializingNodes=$(aws \
                      --output text --region $region ec2 describe-instances \
                      --filters Name=tag-key,Values=PartOf Name=tag-value,Values=FinalProject \
                                Name=instance-state-name,Values=running \
                                Name=tag-key,Values=Name Name=tag-value,Values=INITIALIZING)
}


GetProjectNodes

# While there are no running nodes, wait for nodes to be created
while [[ -z $AllProjectNodes ]]; do
    echo 'Waiting for nodes to be created'
    sleep 10s
    GetProjectNodes
done

GetProjectPendingNodes

# Wait for all pending nodes to start
while [[ ! -z $AllPendingNodes ]]; do
    echo 'Waiting for nodes to start'
    sleep 10s
    GetProjectPendingNodes
done

GetInitializingNodes
# Wait for swarm to initialize
while [[ ! -z $InitializingNodes ]]; do
    echo 'Waiting for swarm nodes'
    sleep 30s
    GetInitializingNodes
done

echo 'Infrastrucre created successfully'


