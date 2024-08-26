#!/bin/bash
echo "系统信息："
echo "主机名：" $(hostname)
echo "内核版本：" $(uname -r)
echo "操作系统：" $(uname -o)
echo "CPU 信息：" $(lscpu | grep 'Model name' | awk '{print $NF}')
echo "内存信息：" $(free -h | grep Mem | awk '{print $2" 总内存，"$3" 已用内存，"$4" 可用内存"}')
echo "磁盘使用情况：" $(df -h | awk '$NF=="/"{print $2" 总容量，"$3" 已用容量，"$4" 可用容量"}')
