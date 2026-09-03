# Fixed Issues

## Ansible Vagrant private-key failure

Older builds used this inventory pattern:

```text
ansible_ssh_private_key_file=/vagrant/.vagrant/machines/k3s-master/virtualbox/private_key
```

That is incorrect when Ansible runs inside `k3s-master`; `.vagrant` is host-side Vagrant state and must not be used as an in-guest SSH dependency.

The corrected design is:

```ini
[local]
localhost ansible_connection=local ansible_python_interpreter=/usr/bin/python3
```

Vagrant shell provisioners configure K3s on the master/workers. Ansible then runs only on the master with `connection: local` to install cluster-wide components through the Kubernetes API.

Validate with:

```powershell
.\scripts\validate-repo.cmd
```
