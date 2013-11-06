<?xml version="1.0" encoding="UTF-8"?>
<slave>
  <name>%(name)s</name>
  <description></description>
  <remoteFS>/home/jenkins</remoteFS>
  <numExecutors>1</numExecutors>
  <mode>NORMAL</mode>
  <retentionStrategy class="hudson.slaves.RetentionStrategy$Always"/>
  <launcher class="hudson.plugins.sshslaves.SSHLauncher" plugin="ssh-slaves@1.2">
    <host>%(host)s</host>
    <port>22</port>
    <credentialsId>a97a282a-458c-4c11-808e-ed2bbf6aaec2</credentialsId>
  </launcher>
  <label></label>
  <nodeProperties/>
  <userId>mirantis-jenkins</userId>
</slave>
