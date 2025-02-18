import tkinter as tk
from tkinter import ttk, messagebox, filedialog
from pyVim.connect import SmartConnect, Disconnect
from pyVmomi import vim
import ssl
import pandas as pd
from tkinter.font import Font
import json
import os
import threading
import logging

class VCenterInspectorApp:
    def __init__(self, root):
        self.root = root
        self.root.title("vCenter 检查工具")
        
        # 设置固定窗口大小
        self.root.geometry("900x370")
        self.root.resizable(False, False)  # 禁止调整窗口大小
        
        # 设置固定字体
        self.default_font = Font(family="Microsoft YaHei", size=10)
        self.root.option_add("*Font", self.default_font)
        
        # 历史记录文件路径
        self.history_file = os.path.join(os.path.expanduser("~"), ".vcenter_history.json")
        self.load_history()
        
        self.setup_logging()
        
        self.create_widgets()
    
    def setup_logging(self):
        log_file = os.path.join(os.path.expanduser("~"), "vcenter_inspector.log")
        logging.basicConfig(
            filename=log_file,
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s'
        )
    
    def load_history(self):
        """加载历史记录"""
        try:
            if os.path.exists(self.history_file):
                with open(self.history_file, 'r', encoding='utf-8') as f:
                    self.history = json.load(f)
            else:
                self.history = {'hosts': [], 'users': []}
        except Exception:
            self.history = {'hosts': [], 'users': []}
    
    def save_history(self):
        """保存历史记录"""
        try:
            with open(self.history_file, 'w', encoding='utf-8') as f:
                json.dump(self.history, f, ensure_ascii=False, indent=2)
        except Exception as e:
            print(f"保存历史记录失败: {e}")
    
    def add_to_history(self, host, user):
        """添加新的历史记录"""
        # 将新记录添加到列表开头
        if host in self.history['hosts']:
            self.history['hosts'].remove(host)
        self.history['hosts'].insert(0, host)
        
        if user in self.history['users']:
            self.history['users'].remove(user)
        self.history['users'].insert(0, user)
        
        # 限制历史记录数量为10个
        self.history['hosts'] = self.history['hosts'][:10]
        self.history['users'] = self.history['users'][:10]
        
        self.save_history()
        
        # 更新下拉菜单
        self.host_combobox['values'] = self.history['hosts']
        self.user_combobox['values'] = self.history['users']
    
    def create_widgets(self):
        # 创建左侧输入区域
        input_frame = ttk.Frame(self.root)
        input_frame.grid(row=0, column=0, padx=10, pady=5, sticky='nsew')
        
        self.host_label = tk.Label(input_frame, text="vCenter 服务器地址:")
        self.host_label.grid(row=0, column=0, padx=10, pady=5, sticky='e')
        self.host_combobox = ttk.Combobox(input_frame, values=self.history['hosts'])
        self.host_combobox.grid(row=0, column=1, padx=10, pady=5, sticky='ew')
        
        self.user_label = tk.Label(input_frame, text="用户名:")
        self.user_label.grid(row=1, column=0, padx=10, pady=5, sticky='e')
        self.user_combobox = ttk.Combobox(input_frame, values=self.history['users'])
        self.user_combobox.grid(row=1, column=1, padx=10, pady=5, sticky='ew')
        
        self.password_label = tk.Label(input_frame, text="密码:")
        self.password_label.grid(row=2, column=0, padx=10, pady=5, sticky='e')
        self.password_entry = tk.Entry(input_frame, show="*")
        self.password_entry.grid(row=2, column=1, padx=10, pady=5, sticky='ew')
        
        self.save_path = tk.StringVar()
        self.path_label = tk.Label(input_frame, text="保存位置:")
        self.path_label.grid(row=3, column=0, padx=10, pady=5, sticky='e')
        self.path_entry = tk.Entry(input_frame, textvariable=self.save_path)
        self.path_entry.grid(row=3, column=1, padx=10, pady=5, sticky='ew')
        self.browse_button = tk.Button(input_frame, text="浏览", command=self.browse_path)
        self.browse_button.grid(row=3, column=2, padx=5, pady=5)
        
        self.inspect_button = tk.Button(input_frame, text="开始检查", command=self.inspect_vcenter)
        self.inspect_button.grid(row=4, column=0, columnspan=3, pady=10)
        
        self.status_label = tk.Label(input_frame, text="")
        self.status_label.grid(row=5, column=0, columnspan=3, pady=5)
        
        # 创建右侧警报显示区域
        alarm_frame = ttk.LabelFrame(self.root, text="实时警报信息")
        alarm_frame.grid(row=0, column=1, padx=10, pady=5, sticky='nsew')
        
        # 创建警报信息表格
        columns = ('对象', '类型', '状态', '警报名称')
        self.alarm_tree = ttk.Treeview(alarm_frame, columns=columns, show='headings', height=15)
        
        # 设置列标题
        for col in columns:
            self.alarm_tree.heading(col, text=col)
            self.alarm_tree.column(col, width=100)
        
        # 添加滚动条
        scrollbar = ttk.Scrollbar(alarm_frame, orient='vertical', command=self.alarm_tree.yview)
        self.alarm_tree.configure(yscrollcommand=scrollbar.set)
        
        self.alarm_tree.grid(row=0, column=0, sticky='nsew')
        scrollbar.grid(row=0, column=1, sticky='ns')
        
        # 配置网格权重
        self.root.grid_columnconfigure(1, weight=1)
        alarm_frame.grid_columnconfigure(0, weight=1)
        input_frame.grid_columnconfigure(1, weight=1)
    
    def browse_path(self):
        filename = filedialog.asksaveasfilename(
            defaultextension=".xlsx",
            filetypes=[("Excel files", "*.xlsx")],
            title="选择保存位置"
        )
        if filename:
            self.save_path.set(filename)
    
    def get_vm_power_state_cn(self, power_state):
        """将虚拟机电源状态转换为中文"""
        state_map = {
            'poweredOn': '已开机',
            'poweredOff': '已关机',
            'suspended': '已挂起'
        }
        return state_map.get(power_state, power_state)

    def get_alarm_status_cn(self, status):
        """将警报状态转换为中文"""
        status_map = {
            'red': '严重',
            'yellow': '警告',
            'green': '正常',
            'gray': '未知'
        }
        return status_map.get(status, status)

    def get_host_status_cn(self, status):
        """将主机状态转换为中文"""
        status_map = {
            'red': '严重',
            'yellow': '警告',
            'green': '正常',
            'gray': '未知'
        }
        return status_map.get(status, status)

    def inspect_vcenter(self):
        # 禁用按钮防止重复点击
        self.inspect_button.config(state='disabled')
        self.status_label.config(text="正在连接...")
        
        # 使用线程执行耗时操作
        threading.Thread(target=self._inspect_vcenter_task, daemon=True).start()

    def _inspect_vcenter_task(self):
        try:
            host = self.host_combobox.get()
            user = self.user_combobox.get()
            password = self.password_entry.get()
            save_path = self.save_path.get()
            
            if not all([host, user, password, save_path]):
                messagebox.showerror("错误", "请填写所有必填项并选择保存位置")
                return
            
            try:
                self.status_label.config(text="正在连接 vCenter 服务器...")
                self.root.update()
                
                context = ssl._create_unverified_context()
                si = SmartConnect(host=host, user=user, pwd=password, sslContext=context)
                
                # 连接成功后保存历史记录
                self.add_to_history(host, user)
                
                content = si.RetrieveContent()
                
                # 清空现有警报显示
                for item in self.alarm_tree.get_children():
                    self.alarm_tree.delete(item)

                # 获取警报信息
                alarm_manager = content.alarmManager
                triggered_alarms = []
                
                # 只遍历主机和虚拟机的警报
                for datacenter in content.rootFolder.childEntity:
                    for cluster in datacenter.hostFolder.childEntity:
                        for host in cluster.host:
                            host_alarms = alarm_manager.GetAlarmState(host)
                            for alarm in host_alarms:
                                if alarm.overallStatus not in ['green', 'gray']:
                                    alarm_info = next((a for a in alarm_manager.GetAlarm(host) if a.key == alarm.key), None)
                                    alarm_data = {
                                        '警报对象': host.name,
                                        '对象类型': '主机',
                                        '警报状态': self.get_alarm_status_cn(alarm.overallStatus),
                                        '警报名称': alarm_info.info.name if alarm_info and hasattr(alarm_info.info, 'name') else '未知',
                                        '警报时间': alarm.time.strftime("%Y-%m-%d %H:%M:%S") if hasattr(alarm, 'time') else '未知',
                                        'timestamp': alarm.time.timestamp() if hasattr(alarm, 'time') else 0
                                    }
                                    triggered_alarms.append(alarm_data)
                                    # 添加到树形视图
                                    self.alarm_tree.insert('', 'end', values=(
                                        alarm_data['警报对象'],
                                        alarm_data['对象类型'],
                                        alarm_data['警报状态'],
                                        alarm_data['警报名称']
                                    ))
                            
                            for vm in host.vm:
                                vm_alarms = alarm_manager.GetAlarmState(vm)
                                for alarm in vm_alarms:
                                    if alarm.overallStatus not in ['green', 'gray']:
                                        alarm_info = next((a for a in alarm_manager.GetAlarm(vm) if a.key == alarm.key), None)
                                        alarm_data = {
                                            '警报对象': vm.name,
                                            '对象类型': '虚拟机',
                                            '警报状态': self.get_alarm_status_cn(alarm.overallStatus),
                                            '警报名称': alarm_info.info.name if alarm_info and hasattr(alarm_info.info, 'name') else '未知',
                                            '警报时间': alarm.time.strftime("%Y-%m-%d %H:%M:%S") if hasattr(alarm, 'time') else '未知',
                                            'timestamp': alarm.time.timestamp() if hasattr(alarm, 'time') else 0
                                        }
                                        triggered_alarms.append(alarm_data)
                                        # 添加到树形视图
                                        self.alarm_tree.insert('', 'end', values=(
                                            alarm_data['警报对象'],
                                            alarm_data['对象类型'],
                                            alarm_data['警报状态'],
                                            alarm_data['警报名称']
                                        ))

                # 收集系统资源数据
                data = []
                host_data = []  # 新增主机数据列表
                for datacenter in content.rootFolder.childEntity:
                    for cluster in datacenter.hostFolder.childEntity:
                        for host in cluster.host:
                            # 收集主机信息
                            host_data.append({
                                '主机名': host.name,
                                'CPU核心数': host.hardware.cpuInfo.numCpuCores,
                                '内存总量(GB)': round(host.hardware.memorySize / 1024 / 1024 / 1024, 2),
                                '处理器型号': host.summary.hardware.cpuModel,
                                '连接状态': host.runtime.connectionState,
                                '运行状态': self.get_host_status_cn(host.overallStatus),
                                'ESXi版本': host.config.product.fullName
                            })

                            for vm in host.vm:
                                # 获取虚拟机硬盘配置
                                disk_size = 0
                                for device in vm.config.hardware.device:
                                    if isinstance(device, vim.VirtualDisk):
                                        disk_size += device.capacityInKB // 1024 // 1024  # 转换为GB
                                
                                # 获取虚拟机备注
                                annotation = vm.config.annotation or "无"
                                
                                data.append({
                                    '虚拟机': vm.name,
                                    '所属主机': host.name,
                                    'vCPU数量': vm.config.hardware.numCPU,
                                    '内存配置(GB)': round(vm.config.hardware.memoryMB / 1024, 2),
                                    '硬盘配置(GB)': disk_size,
                                    '虚拟机状态': self.get_vm_power_state_cn(vm.summary.runtime.powerState),
                                    '备注': annotation
                                })

                self.status_label.config(text="正在保存数据...")
                self.root.update()
                
                # 保存到Excel
                with pd.ExcelWriter(save_path, engine='openpyxl') as writer:
                    # 保存主机信息
                    df_host = pd.DataFrame(host_data)
                    df_host.to_excel(writer, sheet_name='主机资源', index=False)
                    
                    # 保存虚拟机信息
                    df = pd.DataFrame(data)
                    df.to_excel(writer, sheet_name='虚拟机资源', index=False)
                    
                    if triggered_alarms:
                        triggered_alarms.sort(key=lambda x: x['timestamp'], reverse=True)
                        for alarm in triggered_alarms:
                            del alarm['timestamp']
                        df_alarm = pd.DataFrame(triggered_alarms)
                        df_alarm.to_excel(writer, sheet_name='警报信息', index=False)
                
                Disconnect(si)
                
                self.status_label.config(text="检查完成！数据已保存。")
                messagebox.showinfo("完成", f"数据已保存至：\n{save_path}")
                
                logging.info("成功连接到vCenter服务器")
                
            except vim.fault.InvalidLogin:
                messagebox.showerror("错误", "用户名或密码错误")
            except ssl.SSLError:
                messagebox.showerror("错误", "SSL证书验证失败")
            except Exception as e:
                messagebox.showerror("错误", f"发生未知错误: {str(e)}")
        finally:
            # 重新启用按钮
            self.inspect_button.config(state='normal')

if __name__ == "__main__":
    root = tk.Tk()
    app = VCenterInspectorApp(root)
    root.mainloop()
