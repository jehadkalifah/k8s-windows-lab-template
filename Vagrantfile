Vagrant.configure("2") do |config|
  config.vm.box = "bento/ubuntu-24.04"
  config.vm.box_check_update = false
  config.ssh.insert_key = false

  cpus_master = (ENV["K8S_MASTER_CPUS"] || "4").to_i
  mem_master  = (ENV["K8S_MASTER_MEM"]  || "6144").to_i
  cpus_worker = (ENV["K8S_WORKER_CPUS"] || "2").to_i
  mem_worker  = (ENV["K8S_WORKER_MEM"]  || "4096").to_i

  bridge_adapter = ENV["K8S_BRIDGE_ADAPTER"]

  if bridge_adapter.nil? || bridge_adapter.strip.empty?
    abort <<~MSG

      K8S_BRIDGE_ADAPTER is not configured.

      Copy:
        scripts\\lab-config.ps1.example
      to:
        scripts\\lab-config.ps1

      Then set the exact VirtualBox bridged adapter name, for example:
        $env:K8S_BRIDGE_ADAPTER = "Intel(R) Ethernet Connection"

      Run:
        .\\scripts\\show-bridges.ps1
      to see available VirtualBox bridged adapters.

    MSG
  end

  nodes = [
    { name: "k3s-master",  mgmt_ip: "192.168.56.10", cpus: cpus_master, memory: mem_master, role: "server" },
    { name: "k3s-worker1", mgmt_ip: "192.168.56.11", cpus: cpus_worker, memory: mem_worker, role: "agent" },
    { name: "k3s-worker2", mgmt_ip: "192.168.56.12", cpus: cpus_worker, memory: mem_worker, role: "agent" }
  ]

  nodes.each do |node|
    config.vm.define node[:name] do |vm|
      vm.vm.hostname = node[:name]

      # Adapter 1 is Vagrant's default NAT adapter.
      # It gives the VM outbound internet access.

      # Adapter 2: stable host-only management network.
      # Used by K3s control-plane/worker communication and by Windows kubectl.
      vm.vm.network "private_network", ip: node[:mgmt_ip]

      # Adapter 3: bridged onto the real LAN.
      # DHCP is used for the node's LAN address. MetalLB publishes service
      # addresses from a separately reserved LAN range configured below.
      vm.vm.network "public_network",
        bridge: bridge_adapter,
        auto_config: true,
        use_dhcp_assigned_default_route: false

      vm.vm.provider "virtualbox" do |vb|
        vb.name = node[:name]
        vb.cpus = node[:cpus]
        vb.memory = node[:memory]
        vb.linked_clone = true
      end

      if node[:role] == "server"
        vm.vm.provision "shell",
          path: "ansible/bootstrap-master.sh",
          privileged: true
      else
        vm.vm.provision "shell",
          path: "ansible/bootstrap-worker.sh",
          privileged: true

        vm.vm.provision "shell",
          path: "ansible/join-worker.sh",
          privileged: true
      end
    end
  end
end
