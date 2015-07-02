#!/bin/sh
set -e
set -x
#
# This script is meant for quick & easy install via:
#   'curl -sSL https://get.docker.com/ | sh'
# or:
#   'wget -qO- https://get.docker.com/ | sh'
#
#
# Docker Maintainers:
#   To update this script on https://get.docker.com,
#   use hack/release.sh during a normal release,
#   or the following one-liner for script hotfixes:
#     s3cmd put --acl-public -P hack/install.sh s3://get.docker.com/index
#


url='https://get.docker.com/'

# 在运行脚本的时候,我们经常要判断一个命令是否存在
# command命令是bash的build in命令. 使用command命令,会导致找命令的地方就更少了.
# -p导致找命令的时候会使用默认的PATH环境变量值,而不是当前shell的环境变量的值.
# 	也就是所有标准的系统命令都会被找到,但是我们自己添加的路径中的命令就不会被寻找了.
# -V和-v中的任何一个给出来了,那么会输出这个命令的描述而不是真正的执行这个命令,-V会输出详细的描述.
#-V/-v给出的情况下,命令存在会返回0,否则返回1. 不然的话,指定的命令是要被运行的,如果有错误发生,返回127.
# 给出参数是一个命令,如果命令存在,返回0(成功),否则返回1(失败)
command_exists() {
	command -v "$@" >/dev/null 2>&1
}

echo_docker_as_nonroot() {
	your_user=your-user
	[ "$user" != 'root' ] && your_user="$user"
	# intentionally mixed spaces and tabs here -- tabs are stripped by "<<-EOF", spaces are kept in the output
	cat <<-EOF

	If you would like to use Docker as a non-root user, you should now consider
	adding your user to the "docker" group with something like:

	  sudo usermod -aG docker $your_user

	Remember that you will have to log out and back in for this to take effect!

	EOF
}

# 对于一个好的脚本,主要的功能都是要写成一个一个的函数的,这个函数就是这个脚本的入口,就像C中的main一样.
do_install() {

# uname命令是在脚本中经常使用的一个命令,因为linux适配了很多的平台,我们要使用的功能很可能是平台相关的,需要
# 对其进行判断. 常用的选项.
# -m machine. 机器的架构,一般是i686或者是x86_64
# -r release. 就是Linux kernel的版本号.

# docker只有在64位的Linux中才可以运行.
	case "$(uname -m)" in
		*64)
			;;
		*)
			cat >&2 <<-'EOF'
			Error: you are not using a 64bit platform.
			Docker currently only supports 64bit platforms.
			EOF
			exit 1
			;;
	esac

	# docker安装完成之后,其会在/usr/bin中,也就是存在了. 所以如果已经安装了docker,那么就不再安装了.
	if command_exists docker; then
		cat >&2 <<-'EOF'
			Warning: the "docker" command appears to already exist on this system.

			If you already have Docker installed, this script can cause trouble, which is
			why we're displaying this warning and provide the opportunity to cancel the
			installation.

			If you installed the current Docker package using this script and are using it
			again to update Docker, you can safely ignore this message.

			You may press Ctrl+C now to abort this script.
		EOF
		# 注意当已经有docker安装的时候,给出了20秒的时间来让用户按CTRL+C来结束这个脚本. 如果用户在20s中
		# 没有结束这个脚本,那么其会继续运行,一个典型的场景就是当我们想更新docker的时候.
		
		# ()中的命令使用;分开,这里面的所有命令都会在一个子shell(子进程)中运行.
		( set -x; sleep 2 )
	fi

	# $()为命令替换的语法,也就是$()中的命令会在一个子shell中被运行其运行结果的stdout会被返回来被放在$()的
	# 地方.标准错误的部分不会使用. 
	
	# true和false是两个命令,他们什么实际的事情都不做,只是让命令的返回值为0/1
	
	# id命令得到当前用户的各种id. 
	# -g egid. -G所有的gid. -u euid. -r ruid.
	#加上-n,那么返回的就是名字而不是数字.
	
	# 组合起来,当用cxy用户运行的时候,id命令会返回cxy,而且没有错误,那么后面的true命令就不会执行了.返回的值
	# cxy会被放到$()处,那么就是`user=cxy`
	# 如果id命令运行有错误,后面的true命令会导致这个错误不会返回到主script. 如果返回去了,上面设置了`set -e`
	# 会马上退出.
	user=$(id -un 2>/dev/null || true)
	
	# 一般的,我们的脚步都会使用/bin/sh来运行. /bin/sh一般都是一个连接. 在ubuntu中,
	# 以前其是连接到到/bin/bash的,现在连接到了/bin/dash上.
	# dash和bash是差不多的,但是其被优化的更适合于脚步的运行而不是交互.而且其对语法的要求更加严格,
	# 因为其对POSIX表示支持得更好.
	
	# sudo,su都是用来以另外一个用户运行程序的命令.
	
	# 安装docker,我们会下载安装好几个deb包,这是需要使用root权限的,所以需要使用sudo或者是su.
	sh_c='sh -c'
	if [ "$user" != 'root' ]; then
		if command_exists sudo; then
			sh_c='sudo -E sh -c'
		elif command_exists su; then
			sh_c='su -c'
		else
			cat >&2 <<-'EOF'
			Error: this installer needs the ability to run commands as root.
			We are unable to find either "sudo" or "su" available to make this happen.
			EOF
			exit 1
		fi
	fi

	#curl和wget是linux下面下载东西常用的软件.
	
	curl=''
	if command_exists curl; then
		curl='curl -sSL'
	elif command_exists wget; then
		curl='wget -qO-'	
		#grep中的-q是quiet的意思,不向stdout中输出任何的东西,如果找到了任何的匹配,
		#那么马上以状态0退出,就算有错误发生也是这样的.
	elif command_exists busybox && busybox --list-modules | grep -q wget; then
		curl='busybox wget -qO-'
	fi

	# lsb_release命令显示当前系统是哪个Linux的发行版.Linux的发行版太多了.这个脚本为了能在
	# 尽可能多的发行版中运行,需要一些不同的处理.
	# -i就是发行版的id,Ubuntu.
	# -s是short的意思,返回的就是Ubuntu几个字母.
	
	# perform some very rudimentary platform detection
	lsb_dist=''
	if command_exists lsb_release; then
		lsb_dist="$(lsb_release -si)"
	fi
	
	# 大部分的发行版都会提供lsb_release这个命令.如果没有提供这个命令,其也可以通过其他方式得到.
	
	# .(source)是内建命令. 从后面给出的文件中读取并执行其中的命令. 返回的状态是
	# 最后一个命令返回的状态. 如果后面跟的文件名不是以/开头的,也就是不是给出的
	# 绝对路径. 那么会在PATH中指定的路径中搜索这个文件. 如果后面跟了任意的参数,当这个
	# 文件是可以执行的时候,就是这个可执行文件的参数.
	# 这个命令可以看出是和C中的include类似的. 
	# 其不会开启一个新的shell来运行,而是在这个shell中运行. 和在shell中执行一个命令是不同的.
	
	# 如果lsb_release没有确定出是哪个发行版
	# /etc/lsb-release中全部都是A=B这种类型的环境变量的设置,这里source它,然后将里面的
	if [ -z "$lsb_dist" ] && [ -r /etc/lsb-release ]; then
		lsb_dist=$(. /etc/lsb-release && echo "$DISTRIB_ID")
	fi
	if [ -z "$lsb_dist" ] && [ -r /etc/debian_version ]; then
		lsb_dist='debian'
	fi
	if [ -z "$lsb_dist" ] && [ -r /etc/fedora-release ]; then
		lsb_dist='fedora'
	fi
	if [ -z "$lsb_dist" ] && [ -r /etc/os-release ]; then
		lsb_dist=$(. /etc/os-release && echo "$ID")
	fi

	# 将lsb中的所有大写字母变成小写字母
	lsb_dist=$(echo "$lsb_dist" | tr '[:upper:]' '[:lower:]')
	
	# 对于不同的发行版,使用不同的包管理机制. 安装软件使用的命令是不同的. 我使用ubuntu server.
	case "$lsb_dist" in
		amzn|fedora|centos)
			if [ "$lsb_dist" = 'amzn' ]; then
				(
					set -x
					$sh_c 'sleep 3; yum -y -q install docker'
				)
			else
				(
					set -x
					$sh_c 'sleep 3; yum -y -q install docker-io'
				)
			fi
			if command_exists docker && [ -e /var/run/docker.sock ]; then
				(
					set -x
					$sh_c 'docker version'
				) || true
			fi
			echo_docker_as_nonroot
			exit 0
			;;

		'opensuse project'|opensuse|'suse linux'|sled)
			(
				set -x
				$sh_c 'sleep 3; zypper -n install docker'
			)
			if command_exists docker && [ -e /var/run/docker.sock ]; then
				(
					set -x
					$sh_c 'docker version'
				) || true
			fi
			echo_docker_as_nonroot
			exit 0
			;;

		ubuntu|debian|linuxmint|'elementary os'|kali)
		
		# export是sh的build in命令. 被export的名字会出现在后面的所有运行命令的环境变量中.
		# 在shell中,运行一个命令之前,可以使用A=B C=D cmd的方式来运行,这样这个命令运行的时候就有A,C两个环境变量了.
		# 有很多环境变量需要在每个命令运行的时候都设置,如果都手动设置的话,那么就会太麻烦了. export就可以方便的处理这个事情.
		
		# A=B的形式只是在这个sh运行的子进程中设置的环境变量,完成之后,就没有了.
		# export关键字将这个环境变量在这个子进程运行完成之后父进程对应的shell中还有
			export DEBIAN_FRONTEND=noninteractive

		# ()会开启一个子shell,然后在其中运行使用;分开的各个命令. 一般的,其返回值我们是不会使用的. 比如这儿的apt-get update 命令.
			did_apt_get_update=
			apt_get_update() {
				if [ -z "$did_apt_get_update" ]; then
				
					( set -x; $sh_c 'sleep 3; apt-get update' )
					did_apt_get_update=1
				fi
			}
			
			# grep匹配到了会返回0(成功),没有匹配到会返回失败(1)
			
			#modprobe用来进行内核模块的安装. -r参数会从内存中卸载指定的模块. 如果没有-r参数,那么会向内核中插入这个模块.
			
			# !和&&和C中的意思是一样的,!的优先级比&&高,所有下面的意思是系统中没有有aufs这个模块文件,同时这个模块不可以被插入到内核中.

			# grep后面的选项--其实不是一个真正的选项,其用来标示选项已经给完了. 后面给出的是参数了.
			
			# dpkg命令是deb package manager的意思,也就是用来管理系统上的deb包的底层命令. dpkg很底层,包的依赖关系都没有处理.
			# 所以我们一般不会用其来进行包的安装. 但是用来查看包的信息还是很方便的.
			# dpkg -l可以列出包的信息. 没一行的前面两个字符是ii的话,表示这个包已经被安装了.
			
			# aufs is preferred over devicemapper; try to ensure the driver is available.
			if ! grep -q aufs /proc/filesystems && ! $sh_c 'modprobe aufs'; then
				if uname -r | grep -q -- '-generic' && dpkg -l 'linux-image-*-generic' | grep -q '^ii' 2>/dev/null; then
					kern_extras="linux-image-extra-$(uname -r) linux-image-extra-virtual"

					apt_get_update
					
					# apt-get中的-q是quiet的意思.-y是在要回答y/n的时候,直接回到y,脚本就不会停下来等着输入.
					# 所以这两个参数在平时安装软件的时候不会用到,但是在脚本中都会用到.
					( set -x; $sh_c 'sleep 3; apt-get install -y -q '"$kern_extras" ) || true

					if ! grep -q aufs /proc/filesystems && ! $sh_c 'modprobe aufs'; then
						echo >&2 'Warning: tried to install '"$kern_extras"' (for AUFS)'
						echo >&2 ' but we still have no AUFS.  Docker may not work. Proceeding anyways!'
						( set -x; sleep 10 )
					fi
				else
					echo >&2 'Warning: current kernel is not supported by the linux-image-extra-virtual'
					echo >&2 ' package.  We have no AUFS support.  Consider installing the packages'
					echo >&2 ' linux-image-virtual kernel and linux-image-extra-virtual for AUFS support.'
					( set -x; sleep 10 )
				fi
			fi

			# install apparmor utils if they're missing and apparmor is enabled in the kernel
			# otherwise Docker will fail to start
			# 2>/dev/null可以保证在文件不存在的情况下,cat返回no such file or directory到stderr中,此时stdout是空的.
			if [ "$(cat /sys/module/apparmor/parameters/enabled 2>/dev/null)" = 'Y' ]; then
			# command -v返回成功,表示apparmor_parser是存在的.
				if command -v apparmor_parser &> /dev/null; then
					echo 'apparmor is enabled in the kernel and apparmor utils were already installed'
				else
					echo 'apparmor is enabled in the kernel, but apparmor_parser missing'
					apt_get_update
					( set -x; $sh_c 'sleep 3; apt-get install -y -q apparmor' )
				fi
			fi

			# []是测试命令,测试命令的返回要么是0,要么是1. 其为test的命令的一个简单的写法.
			#可以被测试的包括字符串,整数(对它们进行比较操作,和通用编程语言中的一样). 还有文件(就是文件的各种属性)
			# -e表示测试*文件*是否存在.
			if [ ! -e /usr/lib/apt/methods/https ]; then
				apt_get_update
				( set -x; $sh_c 'sleep 3; apt-get install -y -q apt-transport-https ca-certificates' )
			fi
			
			# -z测试字符串是不是为空.
			if [ -z "$curl" ]; then
				apt_get_update
				( set -x; $sh_c 'sleep 3; apt-get install -y -q curl ca-certificates' )
				curl='curl -sSL'
			fi
			
			(
			# [str1 = str2] =是用来测试字符串是否相等的.
				set -x
				if [ "https://get.docker.com/" = "$url" ]; then
					$sh_c "apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 36A1D7869245C8950F966E92D8576A8BA88D21E9"
				elif [ "https://test.docker.com/" = "$url" ]; then
					$sh_c "apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 740B314AE3941731B942C66ADF4FD13717AAD7D6"
				elif [ "https://experimental.docker.com/" = "$url" ]; then
					$sh_c "apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys E33FF7BF5C91D50A6F91FFFD4CC38D40F9A96B49"
				else
					$sh_c "$curl ${url}gpg | apt-key add -"
				fi
				$sh_c "echo deb ${url}ubuntu docker main > /etc/apt/sources.list.d/docker.list"
				$sh_c 'sleep 3; apt-get update; apt-get install -y -q lxc-docker'
			)
			
			if command_exists docker && [ -e /var/run/docker.sock ]; then
				(
					set -x
					$sh_c 'docker version'
				) || true
			fi
			echo_docker_as_nonroot
			exit 0
			;;

		gentoo)
			if [ "$url" = "https://test.docker.com/" ]; then
				# intentionally mixed spaces and tabs here -- tabs are stripped by "<<-'EOF'", spaces are kept in the output
				cat >&2 <<-'EOF'

				  You appear to be trying to install the latest nightly build in Gentoo.'
				  The portage tree should contain the latest stable release of Docker, but'
				  if you want something more recent, you can always use the live ebuild'
				  provided in the "docker" overlay available via layman.  For more'
				  instructions, please see the following URL:'

				    https://github.com/tianon/docker-overlay#using-this-overlay'

				  After adding the "docker" overlay, you should be able to:'

				    emerge -av =app-emulation/docker-9999'

				EOF
				exit 1
			fi

			(
				set -x
				$sh_c 'sleep 3; emerge app-emulation/docker'
			)
			exit 0
			;;
	esac

	# intentionally mixed spaces and tabs here -- tabs are stripped by "<<-'EOF'", spaces are kept in the output
	cat >&2 <<-'EOF'

	  Either your platform is not easily detectable, is not supported by this
	  installer script (yet - PRs welcome! [hack/install.sh]), or does not yet have
	  a package for Docker.  Please visit the following URL for more detailed
	  installation instructions:

	    https://docs.docker.com/en/latest/installation/

	EOF
	exit 1
}

# wrapped up in a function so that we have some protection against only getting
# half the file during "curl | sh"
do_install
