
control 'inetd' do
  impact 1.0
  title 'Do not install inetd'
  desc 'inetd should not be installed'
  describe package('inetd') do
    it { should_not be_installed }
  end
end

control 'auditd' do
  impact 1.0
  title 'Check auditd configuration'
  desc 'auditd provides extended logging capabilities on recent distributions'
  audit_pkg = os.redhat? || os.suse? || os.name == 'amazon' || os.name == 'fedora' || os.name == 'arch' ? 'audit' : 'auditd'
  describe package(audit_pkg) do
    it { should be_installed }
  end
  describe auditd_conf do
    its('log_file') { should cmp '/var/log/audit/audit.log' }
    its('flush') { should match(/^incremental|INCREMENTAL|incremental_async|INCREMENTAL_ASYNC$/) }
    its('disk_error_action') { should cmp 'SUSPEND' }
  end
end
