##
##批量创建虚拟机，虚拟机以文件夹为基准
##注意：虚拟机密码在user_data中修改
#!/bin/bash

current_path=`pwd`
raw_file="/root/Desktop/CentOS-7-x86_64-GenericCloud-20160331_01.raw"
#实例存放地址，绝对地址
vm_instance_path="$current_path/instance"
cloud_init_config_path="$current_path/config_drive"
##各类虚拟机数量
vm_number_admin=1
vm_number_mon=3
vm_number_osd=3
##虚拟机前缀
vm_prefix="default_vm_"
vm_hosts=""
##虚拟机登陆密码（root帐号和ceph帐号）
vm_passwd="password"
##虚拟机实例主机名后缀
vm_host_suffix="kzg"
#vm_hosts=""
##虚拟机IP及GATEWAY设置
ip_prfix="192.168.252."
ip_cluster_prfix="192.168.122."
ip_start_admin=79
ip_start_mon=80
ip_start_osd=90
ip_start_osd_cluster=90
gateway="${ip_prfix}1"
gateway_cluster="${ip_prfix}1"
base_ceph_admin_xml="$current_path/ceph_mon.xml"
base_ceph_mon_xml="$current_path/ceph_mon.xml"
base_ceph_osd_xml="$current_path/ceph_osd.xml"
ssh_key_pub=""

_create_hosts(){
	index=0
	for type in 'admin' 'mon' 'osd'
	do
		if [ "$type" = "admin" ]
		then
			vm_prefix="ceph_admin_"
 			vm_num=$vm_number_admin
 			vm_ip_start=$ip_start_admin
		elif [ "$type" = "mon" ]
		then
			vm_prefix="ceph_mon_"
 			vm_num=$vm_number_mon
 			vm_ip_start=$ip_start_mon
		else
			vm_prefix="ceph_osd_"
 			vm_num=$vm_number_osd
 			vm_ip_start=$ip_start_osd
		fi
		
		for((i=1;i<=$vm_num;i++))
		do
			vm_name=$vm_prefix$i
			let "vm_ip_start=$vm_ip_start+1"
			ip=$ip_prfix$vm_ip_start
			if [ "$index" == "0" ]
			then
				vm_hosts="$vm_hosts - $ip $vm_name $vm_name.$vm_host_suffix"
				index=1
			else
				vm_hosts="$vm_hosts\n - $ip $vm_name $vm_name.$vm_host_suffix"
			fi
		done	
	done
}

_create_vm(){
	##确定虚拟机类型
 	if [ "$1"x = "admin"x ]
	then
		vm_prefix="ceph_admin_"
 		vm_type="admin"
 		vm_num=$vm_number_admin
 		vm_ip_start=$ip_start_admin
		vm_type_xml_file=$base_ceph_admin_xml
 	elif [ "$1"x = "mon"x ]
	then
 		vm_prefix="ceph_mon_"
 		vm_type="mon"
 		vm_num=$vm_number_mon
 		vm_ip_start=$ip_start_mon
		vm_type_xml_file=$base_ceph_mon_xml		 
 	elif [ "$1"x = "osd"x ]
	then
 		vm_prefix="ceph_osd_"
 		vm_type="osd"
 		vm_num=$vm_number_osd
 		vm_ip_start=$ip_start_osd
		vm_type_xml_file=$base_ceph_osd_xml		 
 	else
 		echo "no vm type,exit;"
		return
 	fi

	for((i=1;i<=$vm_num;i++))
	do
		##0.相关变量初始化
		vm_name=$vm_prefix$i
		vm_hostname="$vm_name.$vm_host_suffix"
		vm_path="$vm_instance_path/$vm_name"
		vm_xml_file="$vm_path/vm.xml"		
		vm_vda_file="$vm_path/vda.qcow2"
		##OSD创建额外1个日志盘和3个数据盘
		if [ "$vm_type"x = "osd"x ]
		then
			vm_disk_j_file="$vm_path/disk_j.qcow2"
			for j in 0 1 2
			do
				vm_data[$j]="$vm_path/data_$j.qcow2"
			done
		fi

		let "vm_ip_start=$vm_ip_start+1"
		ip=$ip_prfix$vm_ip_start
		##OSD另一个网络的配置
		if [ "$vm_type"x = "osd"x ]
		then
			let "ip_start_osd_cluster=$ip_start_osd_cluster+1"
			ip_cluster=$ip_cluster_prfix$ip_start_osd_cluster
		fi
		
		driver_config_path="$vm_path/config_drive"
		disk_config_file="$vm_path/config_driver.img"
		meta_data_file="$driver_config_path/openstack/latest/meta_data.json"
		user_data_file="$driver_config_path/openstack/latest/user_data"
		uuid=`uuidgen`
		
		mac_1="fa:92:$(dd if=/dev/urandom count=1 2>/dev/null | md5sum | sed 's/^\(..\)\(..\)\(..\)\(..\).*$/\1:\2:\3:\4/')"
		if [ "$vm_type"x = "osd"x ]
		then
			mac_2="52:54:$(dd if=/dev/urandom count=1 2>/dev/null | md5sum | sed 's/^\(..\)\(..\)\(..\)\(..\).*$/\1:\2:\3:\4/')"
		fi
		
		##1.创建相应的文件
		mkdir -p $vm_path
		mkdir -p $driver_config_path/openstack/2012-08-10
		ln -sv $driver_config_path/openstack/2012-08-10 $driver_config_path/openstack/latest
		cp meta_data.json $meta_data_file
		cp user_data $user_data_file
		
		sed -i "s,%UUID%,$uuid,g" $meta_data_file
		sed -i "s,%HOST%,$vm_hostname,g" $user_data_file
		sed -i "s,%PASSWD%,$vm_passwd,g" $user_data_file
		sed -i "s,%SSH_KEY_INFO%,$ssh_key_pub,g" $user_data_file
		sed -i "s,%IP%,$ip,g" $user_data_file
		sed -i "s,%GATEWAY%,$gateway,g" $user_data_file
		sed -i "s,%HOSTS%,$vm_hosts,g" $user_data_file
		##osd虚拟机需要第二块网卡
		if [ "$vm_type"x = "osd"x ]
		then
			sed -i '/systemctl restart network/d' $user_data_file
		    cat >> $user_data_file <<EOF
 - cp /etc/sysconfig/network-scripts/ifcfg-ens3 /etc/sysconfig/network-scripts/ifcfg-ens6
 - sed -i "s,ens3,ens6,g" /etc/sysconfig/network-scripts/ifcfg-ens6
 - sed -i "s,^IPADDR=.*,IPADDR=$ip_cluster,g" /etc/sysconfig/network-scripts/ifcfg-ens6
 - sed -i "s,^GATEWAY=.*,GATEWAY=$gateway_cluster,g" /etc/sysconfig/network-scripts/ifcfg-ens6
 - systemctl restart network
EOF
        fi
		
		##1.1创建cloud-init镜像
		virt-make-fs $driver_config_path $disk_config_file
		e2label $disk_config_file config-2
		##创建虚拟磁盘文件
		qemu-img create -f qcow2 -o cluster_size=2M,backing_file=$raw_file $vm_vda_file 40G
		##osd需要日志和数据磁盘
		if [ "$vm_type"x = "osd"x ]
		then
			qemu-img create -f qcow2 -o cluster_size=2M $vm_disk_j_file 15G
			for j in 0 1 2
			do
				qemu-img create -f qcow2 -o cluster_size=2M ${vm_data[$j]} 50G
			done
		fi
		
		##1.2创建虚拟机描述文件		
		cp $vm_type_xml_file $vm_xml_file
		sed -i "s,%UUID%,$uuid,g" $vm_xml_file
		sed -i "s,%VM_NAME%,$vm_name,g" $vm_xml_file
		sed -i "s,%DISK_PATH%,$vm_vda_file,g" $vm_xml_file
		sed -i "s,%LOG%,$vm_path/system.log,g" $vm_xml_file
		sed -i "s,%BOOT_PATH%,$disk_config_file,g" $vm_xml_file
		sed -i "s,%MAC_1%,$mac_1,g" $vm_xml_file
		##osd额外配置
		if [ "$vm_type"x = "osd"x ]
		then
			sed -i "s,%DISK_J_PATH%,$vm_disk_j_file,g" $vm_xml_file
			for j in 0 1 2
			do
				sed -i "s,%DISK_D${j}_PATH%,${vm_data[$j]},g" $vm_xml_file		
			done
			sed -i "s,%MAC_2%,$mac_2,g" $vm_xml_file			
		fi

		virsh define $vm_xml_file
		virsh start $vm_name
	done
}

_delete_vm(){
	##确定虚拟机类型
 	if [ "$1"x = "admin"x ]
	then
		vm_prefix="ceph_admin_"
 		vm_num=$vm_number_admin
 	elif [ "$1"x = "mon"x ]
	then
 		vm_prefix="ceph_mon_"
 		vm_num=$vm_number_mon	 
 	elif [ "$1"x = "osd"x ]
	then
 		vm_prefix="ceph_osd_"
 		vm_num=$vm_number_osd	 
 	else
 		echo "no vm type,exit;"
		return
 	fi
	
 	for((i=1;i<=$vm_num;i++))
	do
		virsh destroy $vm_prefix$i
		virsh undefine $vm_prefix$i
		rm -rf $vm_instance_path/$vm_prefix$i
	done
	
}

if [ "$1"x = "-d"x ]
then
	#read -p "确认删除定义的ceph虚拟机（y/n）" result
	#if [ "$result"x = "y"x ]
	#then
	_delete_vm "admin"
	_delete_vm "mon"
	_delete_vm "osd"
	#fi
else
	##生成SSH-KEY
	#read -p "请输入虚拟机中的统一登陆密码：" -s passwd
	#echo ""
	#vm_passwd=$passwd
	if [ ! -f "id_rsa" ]
	then
		ssh-keygen -t rsa -f id_rsa -N ''
	fi
	ssh_key_pub=$(cat id_rsa.pub)
	export LIBGUESTFS_BACKEND=direct
	
	#创建Hosts文件
	_create_hosts
	_create_vm "admin"
	_create_vm "mon"
	_create_vm "osd"
fi