import sys
import os

from datetime import datetime, timedelta
from typing import Dict, List

from alibabacloud_tea_openapi import models as open_api_models
from alibabacloud_ecs20140526.client import Client as EcsClient
from alibabacloud_ecs20140526 import models as ecs_models
from alibabacloud_tea_util import models as util_models

from alibabacloud_darabonba_env.client import Client as EnvClient
from alibabacloud_darabonba_string.client import Client as StringClient


class SimpleClient:
    def __init__(self):
        pass

    # constant
    VPN_SECURITY_GROUP = "socks"

    # get alive time after minutes
    # return: UTC+0, format should be yyyy-MM-ddTHH:mm:00Z
    @staticmethod
    def getAliveTime(alive_minutes: int) -> str:
        if alive_minutes < 30:
            alive_minutes = 30

        utc_now = datetime.utcnow()
        utc_later = utc_now + timedelta(minutes=alive_minutes)
        return utc_later.strftime('%Y-%m-%dT%H:%M:00Z')

    # access configuration
    @staticmethod
    def accessConfig(endpoint: str = "ecs.aliyuncs.com") -> open_api_models.Config:
        config = open_api_models.Config(
            access_key_id=EnvClient.get_env("ALIBABA_CLOUD_ACCESS_KEY_ID"),
            access_key_secret=EnvClient.get_env("ALIBABA_CLOUD_ACCESS_KEY_SECRET"),
            endpoint=endpoint,
            connect_timeout=5000,
            read_timeout=5000,
        )
        return config

    # describe instances in regions
    @staticmethod
    def describeInstances(region_ids: List[str]):
        config = SimpleClient.accessConfig()
        client = EcsClient(config)

        for region_id in region_ids:
            request = ecs_models.DescribeInstancesRequest(
                region_id=region_id, page_size=100
            )
            try:
                response = client.describe_instances(request)
            except expression as e:
                print(e.message)
                return

            instances = response.body.instances.instance
            print(f"ECS instances list in {region_id}")
            for index, instance in enumerate(instances):
                print(
                    "".join(
                        [
                            f"{index + 1} {instance.host_name}", "\n",
                            f"InstanceID:{instance.instance_id} CPU:{instance.cpu} Memory:{int(instance.memory/1024)}GB", "\n",
                            f"Spec：{instance.instance_type} OS:{instance.ostype}({instance.osname})", "\n",
                            f"Status：{instance.status}",
                        ]
                    )
                )

    # describe attributes of instance
    @staticmethod
    def describeInstanceAttribute(region_id: str, instance_id: str):
        config = SimpleClient.accessConfig()
        client = EcsClient(config)

        try:
            # instance attribute
            describe_instance_attribute_request = (
                ecs_models.DescribeInstanceAttributeRequest(instance_id=instance_id)
            )
            describe_instance_attribute_response = (
                client.describe_instance_attribute_with_options(
                    describe_instance_attribute_request, util_models.RuntimeOptions()
                )
            )
            instance = describe_instance_attribute_response.body
            print(f"ECS instance {instance_id} info")
            print(
                "".join(
                    [
                        # summary
                        f"creation_time: {instance.creation_time}", "\n",
                        f"instance_charge_type: {instance.instance_charge_type}", "\n",
                        f"region_id: {instance.region_id}", "\n",
                        # instance and image
                        f"instance_type: {instance.instance_type}", "\n",
                        f"cpu: {instance.cpu}", "\n",
                        f"memory: {instance.memory}", "\n",
                        f"image_id: {instance.image_id}", "\n",
                        # internet
                        f"internet_charge_type: {instance.internet_charge_type}", "\n",
                        f"public_ip_address: {instance.public_ip_address.ip_address}", "\n",
                        f"internet_max_bandwidth_in: {instance.internet_max_bandwidth_in}", "\n",
                        f"internet_max_bandwidth_out: {instance.internet_max_bandwidth_out}", "\n",
                        f"security_group_id: {instance.security_group_ids.security_group_id}"
                    ]
                )
            )
            # disk
            describe_disks_request = ecs_models.DescribeDisksRequest(
                region_id=region_id, instance_id=instance_id, disk_type="system"
            )
            describe_disks_response = client.describe_disks_with_options(
                describe_disks_request, util_models.RuntimeOptions()
            )
            disks = describe_disks_response.body.disks.disk
            print(f"ECS instance {instance_id} disk info")
            for disk in disks:
                print(
                    "".join(
                        [
                            f"category: {disk.category}", "\n"
                            f"size: {disk.size} GB", "\n"
                            f"delete_with_instance: {disk.delete_with_instance}"
                        ]
                    )
                )
            # user data
            describe_user_data_request = ecs_models.DescribeUserDataRequest(
                region_id=region_id, instance_id=instance_id
            )
            describe_user_data_response = client.describe_user_data_with_options(
                describe_user_data_request, util_models.RuntimeOptions()
            )
            user_data = describe_user_data_response.body.user_data
            print(f"user_data: {user_data}")
        except Exception as e:
            print(e.message)

    # reboot instance
    @staticmethod
    def rebootInstance(instance_id: str):
        # config = SimpleClient.accessConfig(f'ecs.{region_id}.aliyuncs.com')
        config = SimpleClient.accessConfig()
        client = EcsClient(config)

        request = ecs_models.RebootInstanceRequest(instance_id=instance_id)
        runtime = util_models.RuntimeOptions()
        try:
            client.reboot_instance_with_options(request, runtime)
            print(
                f"ECS instance {instance_id} has been rebooted"
            )
        except Exception as e:
            print(e.message)

    # delete instance
    @staticmethod
    def deleteInstance(instance_id: str):
        config = SimpleClient.accessConfig()
        client = EcsClient(config)

        request = ecs_models.DeleteInstanceRequest(instance_id=instance_id, force=True)
        runtime = util_models.RuntimeOptions()
        try:
            client.delete_instance_with_options(request, runtime)
            print(
                f"ECS instance {instance_id} has been released"
            )
        except Exception as e:
            print(e.message)

    # set auto release time
    @staticmethod
    def autoReleaseInstance(instance_id: str, alive_minutes: int):
        config = SimpleClient.accessConfig()
        client = EcsClient(config)

        auto_release_tm = SimpleClient.getAliveTime(alive_minutes)
        request = ecs_models.ModifyInstanceAutoReleaseTimeRequest(
            instance_id=instance_id, auto_release_time=auto_release_tm
        )
        runtime = util_models.RuntimeOptions()
        try:
            client.modify_instance_auto_release_time_with_options(request, runtime)
            print(
                f"ECS instance {instance_id} has been set to release at {auto_release_tm}"
            )
        except Exception as e:
            print(e.message)

    # price
    # security group
    # retrieve
    # add
    # delete
    # ai

    # 付费类型 按量计费 PostPaid
    # 地域 美国硅谷 us-west-1
    # 实例个数 1
    # 规格
    # ecs.xn4.small 1vCPU1GiB
    # ecs.n4.small 1vCPU2GiB
    # ecs.u1-c1m1.large 2vCPU2GiB
    # ecs.u1-c1m2.large 2vCPU4GiB

    # 镜像 ubuntu 22.04 64 ubuntu_22_04_x64_20G_alibase_20240530.vhd
    # 系统盘 ESSD 20G 随实例释放 cloud_essd
    # 公网IP 分配IPv4
    # 带宽计费模式 固定带宽 3Mbps PayByBandwidth
    # 安全组 新建 默认 记得删除
    # 登录凭证 自定义密码
    # 自定义数据

    # @staticmethod
    # def runInstances(
    #     args: List[str],
    # ) -> None:
    #     config = SimpleClient.accessConfig()
    #     client = EcsClient(config)
    #     system_disk = ecs_models.RunInstancesRequestSystemDisk(
    #         size='20',
    #         category='cloud_essd'
    #     )
    #     run_instances_request = ecs_20140526_models.RunInstancesRequest(
    #         region_id='us-west-1',
    #         image_id='ubuntu_22_04_x64_20G_alibase_20240530.vhd',
    #         instance_type='ecs.n4.small',
    #         internet_charge_type='PayByBandwidth',
    #         system_disk=system_disk,
    #         user_data='',
    #         amount=1,
    #         auto_release_time='2018-01-01T12:05:00Z',
    #         instance_charge_type='PostPaid',
    #         password='3214321'
    #     )
    #     runtime = util_models.RuntimeOptions()
    #     try:
    #         client.run_instances_with_options(run_instances_request, runtime)
    #     except Exception as error:
    #         print(error.message)

    # describe security groups
    # option parameter: region_id, security_group_name(optional)
    # return security_group_ids
    @staticmethod
    def describeSecurityGroups(**kwargs: Dict) -> List[str]:
        region_id = kwargs.get("region_id")
        config = SimpleClient.accessConfig()
        client = EcsClient(config)
        runtime = util_models.RuntimeOptions()

        try:
            # groups
            security_groups_request = ecs_models.DescribeSecurityGroupsRequest(**kwargs)
            security_groups_response = client.describe_security_groups_with_options(
                security_groups_request, runtime
            )
            security_groups = security_groups_response.body.security_groups.security_group
            # attr info
            for group in security_groups:
                group_id = group.security_group_id
                group_name = group.security_group_name
                group_attr_request = ecs_models.DescribeSecurityGroupAttributeRequest(
                    region_id=region_id, security_group_id=group_id
                )
                security_group_response = client.describe_security_group_attribute_with_options(
                    group_attr_request, runtime
                )
                permissions = security_group_response.body.permissions.permission

                print(f"Security group {group_id}/{group_name} info")
                for permission in permissions:
                    print(
                        "".join(
                            [
                                f"direction: {permission.direction}", "\n",
                                f"policy: {permission.policy}", "\n",
                                f"priority: {permission.priority}", "\n",
                                f"ip_protocol: {permission.ip_protocol}", "\n",
                                f"port_range: {permission.port_range}", "\n",
                                f"source_cidr_ip: {permission.source_cidr_ip}"
                            ]
                        )
                    )
            return [group.security_group_id for group in security_groups]
        except Exception as e:
            print(e.message)

    # retrieve security group id by name
    # create security group with permissions(ICMP-1, TCP22, TCP5000, TCP/UDP3389) if not exist
    # create instance with joining the security group
    # add/delete permission in security group

    # retrieve instance's public ip, create time and release time
    # delete instance
    # delete security group that not related to any instance

    # create security group with initial permissions
    # parameter: region_id
    # return security_group_id
    @staticmethod
    def createSecurityGroup(region_id: str) -> str:
        config = SimpleClient.accessConfig()
        client = EcsClient(config)
        runtime = util_models.RuntimeOptions()
        # create security group
        create_security_group_request = ecs_models.CreateSecurityGroupRequest(
            region_id=region_id, security_group_name=SimpleClient.VPN_SECURITY_GROUP
        )
        try:
            create_security_group_response = client.create_security_group_with_options(
                create_security_group_request, runtime
            )
        except Exception as e:
            print('Exception when create security group')
            print(e.message)
            return
        security_group_id = create_security_group_response.body.security_group_id
        print(f'security group {security_group_id} has been created')
        # initialize permissions
        permissions = [
            ecs_models.AuthorizeSecurityGroupRequestPermissions(**v)
            for v in SimpleClient.getInitialPermissions()
        ]
        authorize_security_group_request = ecs_models.AuthorizeSecurityGroupRequest(
            region_id=region_id,
            security_group_id=security_group_id,
            permissions=permissions
        )
        try:
            client.authorize_security_group_with_options(authorize_security_group_request, runtime)
        except Exception as e:
            print('Exception when initialize permissions')
            print(e.message)
            return
        print(f'security group {security_group_id} has been initialized')
        return security_group_id

    # get initial permissions
    # TCP22, RDP3389, ICMP-1, TCP5000, TCP/UDP8388
    # return list of permissons
    @staticmethod
    def getInitialPermissions() -> List[Dict]:
        return [
            {
                "policy": "accept",
                "ip_protocol": "TCP",
                "port_range": "22/22",
                "source_cidr_ip": "0.0.0.0/0",
                "description": "SSH",
            },
            {
                "policy": "accept",
                "ip_protocol": "TCP",
                "port_range": "3389/3389",
                "source_cidr_ip": "0.0.0.0/0",
                "description": "RDP",
            },
            {
                "policy": "accept",
                "ip_protocol": "ICMP",
                "port_range": "-1/-1",
                "source_cidr_ip": "0.0.0.0/0",
                "description": "ICMP",
            },
            {
                "policy": "accept",
                "ip_protocol": "TCP",
                "port_range": "5000/5000",
                "source_cidr_ip": "0.0.0.0/0",
                "description": "FlaskHttp",
            },
            {
                "policy": "accept",
                "ip_protocol": "TCP",
                "port_range": "8388/8388",
                "source_cidr_ip": "0.0.0.0/0",
                "description": "vpn",
            },
            {
                "policy": "accept",
                "ip_protocol": "UDP",
                "port_range": "8388/8388",
                "source_cidr_ip": "0.0.0.0/0",
                "description": "vpn",
            },
        ]

    # add permissions in security group
    # parameter: region_id, security_group_id, port
    # return true when success, false when fail
    @staticmethod
    def addPermissions(region_id: str, security_group_id: str, port: int) -> bool:
        config = SimpleClient.accessConfig()
        client = EcsClient(config)
        runtime = util_models.RuntimeOptions()
        # add permissions
        permissions = [
            ecs_models.AuthorizeSecurityGroupRequestPermissions(**v)
            for v in SimpleClient.getPermListByPort(port)
        ]
        authorize_security_group_request = ecs_models.AuthorizeSecurityGroupRequest(
            region_id=region_id,
            security_group_id=security_group_id,
            permissions=permissions
        )
        try:
            client.authorize_security_group_with_options(authorize_security_group_request, runtime)
        except Exception as e:
            print('Exception when add permissions')
            print(e.message)
            return False
        print(f'TCP/UDP {port} has been added to security group')
        return True

    # remove permissions in security group
    # parameter: region_id, security_group_id, port
    # return true when success, false when fail
    @staticmethod
    def removePermissions(region_id: str, security_group_id: str, port: int) -> bool:
        config = SimpleClient.accessConfig()
        client = EcsClient(config)
        runtime = util_models.RuntimeOptions()
        # remove permissions
        permissions = [
            ecs_models.RevokeSecurityGroupRequestPermissions(**v)
            for v in SimpleClient.getPermListByPort(port)
        ]
        revoke_security_group_request = ecs_models.RevokeSecurityGroupRequest(
            region_id=region_id,
            security_group_id=security_group_id,
            permissions=permissions
        )
        try:
            client.revoke_security_group_with_options(revoke_security_group_request, runtime)
        except Exception as e:
            print('Exception when remove permissions')
            print(e.message)
            return False
        print(f'TCP/UDP {port} has been removed from security group')
        return True

    # get permissions by port
    # parameters: port
    # return list of TCP/UDP permissons
    @staticmethod
    def getPermListByPort(port: int) -> List[Dict]:
        return [
            {
                "policy": "accept",
                "ip_protocol": "TCP",
                "port_range": f"{port}/{port}",
                "source_cidr_ip": "0.0.0.0/0",
                "description": "vpn",
            },
            {
                "policy": "accept",
                "ip_protocol": "UDP",
                "port_range": f"{port}/{port}",
                "source_cidr_ip": "0.0.0.0/0",
                "description": "vpn",
            },
        ]


if __name__ == "__main__":
    # region_ids = StringClient.split(sys.argv[1], ',', 50)
    # SimpleClient.describeInstances(region_ids)

    # region_id = sys.argv[1]
    # instance_id = sys.argv[2]
    # SimpleClient.describeInstanceAttribute(region_id, instance_id)

    region_id = sys.argv[1]
    security_group_name = sys.argv[2]
    # group_id = SimpleClient.createSecurityGroup(region_id)
    # if SimpleClient.addPermissions(region_id, group_id, 9000):
    #     print("nice")
    # SimpleClient.removePermissions(region_id, group_id, 9000)

    #SimpleClient.describeSecurityGroups(region_id=region_id)
    print(SimpleClient.describeSecurityGroups(region_id=region_id, security_group_name=security_group_name))
    # SimpleClient.rebootInstance(region_id, instance_id)
    # SimpleClient.delete(region_id, instance_id)
