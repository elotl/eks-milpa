#!/bin/bash

if [[ "$1" != "" ]]; then
    VPC_ID="$1"
fi

if [[ "$VPC_ID" = "" ]]; then
    echo "Please provide VPC_ID."
    exit 1
fi

aws --version || {
    echo "Missing command line tool: aws"
    exit 1
}

jq --version || {
    echo "Missing command line tool: jq"
    exit 1
}

# Delete instances in VPC.
while true; do
    instances=$(aws ec2 describe-instances | jq -r ".Reservations | .[] | .Instances | .[] | select(.State.Name!=\"terminated\") | select(.VpcId==\"$VPC_ID\") | .InstanceId")
    if [[ "$instances" != "" ]]; then
        echo "Terminating instances \"$instances\""
        aws ec2 terminate-instances --instance-ids $instances
    else
        break
    fi
done

# Delete LBs.
while true; do
    lbs=$(aws elb describe-load-balancers | jq -r ".LoadBalancerDescriptions | .[] | select(.VPCId==\"$VPC_ID\") | .LoadBalancerName")
    if [[ "$lbs" != "" ]]; then
        echo "Deleting LBs \"$lbs\""
        for lb in $lbs; do
            aws elb delete-load-balancer --load-balancer-name $lb
        done
    else
        break
    fi
done

# Delete security groups in VPC.
for sg in $(aws ec2 describe-security-groups | jq -r ".SecurityGroups | .[] | select(.VpcId == \"$VPC_ID\") | .GroupId"); do
    aws ec2 delete-security-group --group-id $sg
done

# Delete route tables in VPC.
for rt in $(aws ec2 describe-route-tables | jq -r ".RouteTables | .[] | select(.VpcId == \"$VPC_ID\") | .RouteTableId"); do
    for cidr in $(aws ec2 describe-route-tables | jq -r ".RouteTables | .[] | select(.RouteTableId == \"$rt\") | .Routes | .[] | .DestinationCidrBlock"); do
        aws ec2 delete-route --route-table-id $rt --destination-cidr $cidr
    done
    aws ec2 delete-route-table --route-table-id $rt
done

exit 0
