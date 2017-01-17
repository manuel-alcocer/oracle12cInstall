#!/usr/bin/env bash

set -e

addgroup --system oinstall
addgroup --system dba
adduser --system --ingroup oinstall --shell /bin/bash oracle
adduser oracle dba

memorysize=$(free -b | grep -Ei 'mem:' | awk '{print $2}')
memorymax=$((memorysize*40))
memorymax=$((memorymax/100))
pagesize=$(getconf PAGE_SIZE)
shmall=$((memorysize/pagesize))
((memorysize--))

currentdir=$(pwd)

cat << EOF > /etc/sysctl.d/local-oracle.conf
fs.file-max = 65536
fs.aio-max-nr = 1048576
# semaphores: semmsl, semmns, semopm, semmni
kernel.sem = 250 32000 100 128
# (Oracle recommends total machine Ram -1 byte)
kernel.shmmax = $memorysize
# shmall: amount of shared memory pages: shmmax/PAGE_SIZE
# PAGESIZE: $ getconf PAGE_SIZE
# shmmax > shmall * PAGE_SIZE
kernel.shmall = $shmall
# PAGE_SIZE
kernel.shmmni = 4096
net.ipv4.ip_local_port_range = 1024 65000
vm.hugetlb_shm_group = 111
vm.nr_hugepages = 64
EOF

sysctl -p /etc/sysctl.d/local-oracle.conf

cat << EOF > /etc/security/limits.d/local-oracle.conf
oracle          soft    nproc           2047
oracle          hard    nproc           16384
oracle          soft    nofile          1024
oracle          hard    nofile          65536
EOF

ln -s /usr/bin/awk /bin/awk
ln -s /usr/bin/basename /bin/basename
ln -s /usr/bin/rpm /bin/rpm
ln -s /usr/lib/x86_64-linux-gnu /usr/lib64

mkdir -p /opt/oracle/product/12.1.0.2
mkdir -p /opt/oraInventory
chown -R oracle:dba /opt/oracle/
chown -R oracle:dba /opt/oraInventory

apt -y install build-essential binutils libcap-dev gcc g++ libc6-dev ksh libaio-dev make libxi-dev libxtst-dev libxau-dev libxcb1-dev sysstat rpm xauth unzip rlwrap

read -p 'Nombre de la base de datos: ' oracleDBname

cat << EOF > /home/oracle/.profile
export ORACLE_HOSTNAME=localhost
export ORACLE_OWNER=oracle
export ORACLE_BASE=/opt/oracle
export ORACLE_HOME=/opt/oracle/product/12.1.0.2/db_home_1
export ORACLE_UNQNAME=$oracleDBname
export ORACLE_SID=$oracleDBname
export PATH=\$PATH:\$ORACLE_HOME/bin
export LD_LIBRARY_PATH=\$LD_LIBRARY_PATH:/usr/lib/x86_64-linux-gnu:/bin/lib:/lib/x86_64-linux-gnu/:/usr/lib64
export LD_LIBRARY_PATH=/opt/oracle/instantclient_12_1:\$LD_LIBRARY_PATH
export PATH=/opt/oracle/instantclient_12_1:\$PATH
alias sql="$(which rlwrap) sqlplus $@"
EOF

chown -R oracle. /home/oracle

printf 'Introducir la clave para el usuario oracle: \n'
passwd oracle

ORACLEDISK1='linuxamd64_12102_database_1of2.zip'
ORACLEDISK2='linuxamd64_12102_database_2of2.zip'

unzip $ORACLEDISK1
unzip $ORACLEDISK2

printf 'inventory_loc=/opt/oraInventory\ninst_group=oinstall\n' > /etc/oraInst.loc

read -p 'Introduce la contraseña para la BBDD: ' oraclePassword

cat << EOF > dbresponsefile.rsp
oracle.install.responseFileVersion=/oracle/install/rspfmt_dbinstall_response_schema_v12.1.0
oracle.install.option=INSTALL_DB_AND_CONFIG
ORACLE_HOSTNAME=localhost
UNIX_GROUP_NAME=oinstall
INVENTORY_LOCATION=/opt/oraInventory
SELECTED_LANGUAGES=es_ES,en,es
ORACLE_HOME=/opt/oracle/product/12.1.0.2/db_home_1
ORACLE_BASE=/opt/oracle
oracle.install.db.InstallEdition=EE
oracle.install.db.DBA_GROUP=dba
oracle.install.db.OPER_GROUP=dba
oracle.install.db.BACKUPDBA_GROUP=dba
oracle.install.db.DGDBA_GROUP=dba
oracle.install.db.KMDBA_GROUP=dba
oracle.install.db.isRACOneInstall=false
oracle.install.db.rac.serverpoolCardinality=0
oracle.install.db.config.starterdb.type=GENERAL_PURPOSE
oracle.install.db.config.starterdb.globalDBName=$oracleDBname
oracle.install.db.config.starterdb.SID=$oracleDBname
oracle.install.db.ConfigureAsContainerDB=true
oracle.install.db.config.PDBName=pdborcl
oracle.install.db.config.starterdb.password.ALL=$oraclePassword
oracle.install.db.config.starterdb.characterSet=AL32UTF8
oracle.install.db.config.starterdb.memoryOption=true
oracle.install.db.config.starterdb.memoryLimit=$memorymax
oracle.install.db.config.starterdb.installExampleSchemas=true
oracle.install.db.config.starterdb.managementOption=DEFAULT
oracle.install.db.config.starterdb.omsPort=0
oracle.install.db.config.starterdb.enableRecovery=false
oracle.install.db.config.starterdb.storageType=FILE_SYSTEM_STORAGE
oracle.install.db.config.starterdb.fileSystemStorage.dataLocation=/opt/oracle/oradata
SECURITY_UPDATES_VIA_MYORACLESUPPORT=false
DECLINE_SECURITY_UPDATES=true
EOF

sudo -i -u oracle ${currentdir}/database/runInstaller -waitforcompletion -silent -showProgress -responseFile ${currentdir}/dbresponsefile.rsp

/opt/oraInventory/orainstRoot.sh
/opt/oracle/product/12.1.0.2/db_home_1/root.sh

cat << EOF > cfgrsp.properties
oracle.assistants.server|S_SYSPASSWORD=${oraclePassword}
oracle.assistants.server|S_SYSTEMPASSWORD=${oraclePassword}
oracle.assistants.server|S_SYSMANPASSWORD=${oraclePassword}
oracle.assistants.server|S_DBSNMPPASSWORD=${oraclePassword}
oracle.assistants.server|S_HOSTUSERPASSWORD=${oraclePassword}
oracle.assistants.server|S_ASMSNMPPASSWORD=${oraclePassword}
EOF

sudo -i -u oracle /opt/oracle/product/12.1.0.2/db_home_1/cfgtoollogs/configToolAllCommands RESPONSE_FILE=${currentdir}/cfgrsp.properties

cat << EOF > netca.rsp
[GENERAL]
RESPONSEFILE_VERSION="12.1"
CREATE_TYPE="CUSTOM"
[oracle.net.ca]
INSTALLED_COMPONENTS={"server","net8","javavm"}
INSTALL_TYPE=""typical""
LISTENER_NUMBER=1
LISTENER_NAMES={"LISTENER"}
LISTENER_PROTOCOLS={"TCP;1521"}
LISTENER_START=""LISTENER""
NAMING_METHODS={"TNSNAMES","ONAMES","HOSTNAME"}
NSN_NUMBER=1
NSN_NAMES={"EXTPROC_CONNECTION_DATA"}
NSN_SERVICE={"PLSExtProc"}
NSN_PROTOCOLS={"TCP;HOSTNAME;1521"}
EOF

sudo -i -u oracle /opt/oracle/product/12.1.0.2/db_home_1/bin/netca -silent -responsefile ${currentdir}/netca.rsp

cat << EOF > dbca.rsp
[GENERAL]
RESPONSEFILE_VERSION = "12.1.0"
OPERATION_TYPE = "createDatabase"
[CREATEDATABASE]
GDBNAME = "${oracleDBname}"
SID = "${oracleDBname}"
TEMPLATENAME = "General_Purpose.dbc"
SYSPASSWORD = "${oraclePassword}"
SYSTEMPASSWORD = "${oraclePassword}"
CHARACTERSET = "AL32UTF8"
NATIONALCHARACTERSET= "UTF8"
[createTemplateFromDB]
SOURCEDB = "myhost:1521:${oracleDBname}"
SYSDBAUSERNAME = "system"
TEMPLATENAME = "My Copy TEMPLATE"
[createCloneTemplate]
SOURCEDB = "${oracleDBname}"
TEMPLATENAME = "My Clone TEMPLATE"
[DELETEDATABASE]
SOURCEDB = "${oracleDBname}"
[generateScripts]
TEMPLATENAME = "New Database"
GDBNAME = "$(hostname -f)"
[CONFIGUREDATABASE]
[ADDINSTANCE]
DB_UNIQUE_NAME = "$(hostname -f)"
SYSDBAUSERNAME = "sys"
[DELETEINSTANCE]
DB_UNIQUE_NAME = "$(hostname -f)"
INSTANCENAME = "${oracleDBname}"
SYSDBAUSERNAME = "sys"
[CREATEPLUGGABLEDATABASE]
SOURCEDB = "${oracleDBname}"
PDBNAME = "PDB1"
[UNPLUGDATABASE]
SOURCEDB = "${oracleDBname}"
PDBNAME = "PDB1"
ARCHIVETYPE = "TAR"
[DELETEPLUGGABLEDATABASE]
SOURCEDB = "${oracleDBname}"
PDBNAME = "PDB1"
[CONFIGUREPLUGGABLEDATABASE]
SOURCEDB = "${oracleDBname}"
PDBNAME = "PDB1"
EOF

sudo -i -u oracle /opt/oracle/product/12.1.0.2/db_home_1/bin/dbca -silent -cloneTemplate -responseFile ${currentdir}/dbca.rsp

CLIENTBASIC='instantclient-basic-linux.x64-12.1.0.2.0.zip'
CLIENTSQL='instantclient-sqlplus-linux.x64-12.1.0.2.0.zip'

sudo -i -u oracle unzip ${currentdir}/${CLIENTBASIC} -d /opt/oracle
sudo -i -u oracle unzip ${currentdir}/${CLIENTSQL} -d /opt/oracle
sudo -i -u oracle ln -s /opt/oracle/instantclient_12_1/libclntsh.so{.12.1,}
sudo -i -u oracle ln -s /opt/oracle/instantclient_12_1/libocci.so{.12.1,}

set +e
