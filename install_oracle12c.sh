#!/usr/bin/env bash

NUMERRS=0
ERRS=()

WARNNUMS=0
WARNINGS=()

currentdir=$(pwd)

function comprobarErrores(){
    if [[ ${#NUMERRS[@]} > 0 ]]; then
        printf 'Errores detectados...\n'
        for ERRORMSG in "${ERRS[@]}"; do
            printf "${ERRORMSG}\n"
        done
    fi
}

function comprobarWarnings(){
    if [[ ${#WARNNUMS[@]} > 0 ]]; then
        printf 'Warnings detectados...\n'
        for WARNMSG in "${WARNINGS[@]}"; do
            printf "${WARNMSG}\n"
        done
    fi
}

function Salir(){
    exit 1
}

printf 'Instalassiom de Oracle12c en GNU/Lìnu...\n'

printf 'Comprobando prerreqs..\n'
if [[ ! $(dpkg-query -s sudo | grep -Ei 'Status: install ok installed') ]]; then
    printf 'Error grave: Instala sudo para seguir\n'
    exit 1
fi
if [[ ! $(id -u) -eq 0 ]]; then
    printf 'Error grave: Este script solo lo puede ejecutar root...\n'
    exit 1
fi

ACTION='Configurando cuentas de usuario necesarias'
printf "${ACTION}...\n"
if [[ ! $(grep -E '^oinstall:' /etc/group) ]]; then
    addgroup --system oinstall
    if [[ $? > 0 ]]; then
        ((NUMERRS++))
        ERRS+=("Error ${ACTION}")
    fi
fi

ACTION='Creando grupo dba'
printf "${ACTION}...\n"
if [[ ! $(grep -E '^dba:' /etc/group) ]]; then
    addgroup --system dba
    if [[ $? > 0 ]]; then
        ((NUMERRS++))
        ERRS+=("Error ${ACTION}")
    fi
fi

ACTION='Creando usuario oracle'
printf "${ACTION}...\n"
if [[ ! $(grep -E '^oracle:' /etc/passwd) ]]; then
    adduser --system --ingroup oinstall --shell /bin/bash oracle
    if [[ $? > 0 ]]; then
        ((NUMERRS++))
        ERRS+=("Error ${ACTION}")
    fi
fi
   
ACTION='Añadiendo usuario oracle al grupo dba'
printf "${ACTION}...\n"
adduser oracle dba 1>/dev/null
if [[ $? > 0 ]]; then
    ((NUMERRS++))
    ERRS+=("Error ${ACTION}")
fi

printf 'Calculando valores de memoria...\n'
memorysize=$(free -b | grep -Ei 'mem:' | awk '{print $2}')
memorymax=$(free -m | grep -Ei 'mem:' | awk '{print $4}')
memorymax=$((memorymax*40/100))
pagesize=$(getconf PAGE_SIZE)
shmall=$((memorysize/pagesize))
((memorysize--))

ACTION='Creando configuración de kernel'
printf "${ACTION}...\n" 
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
if [[ $? > 0 ]]; then
    ((NUMERRS++))
    ERRS+=("Error ${ACTION}")
fi

ACTION='Actualizando valores del kernel'
printf "${ACTION}...\n" 
sysctl -p /etc/sysctl.d/local-oracle.conf
if [[ $? > 0 ]]; then
    ((NUMERRS++))
    ERRS+=("Error ${ACTION}")
fi


ACTION='Estableciendo límites de ficheros'
printf "${ACTION}...\n" 
cat << EOF > /etc/security/limits.d/local-oracle.conf
oracle          soft    nproc           2047
oracle          hard    nproc           16384
oracle          soft    nofile          1024
oracle          hard    nofile          65536
EOF
if [[ $? > 0 ]]; then
    ((NUMERRS++))
    ERRS+=("Error ${ACTION}")
fi


ACTION='Creando softlinks necesarios'
printf "${ACTION}...\n" 
ln -s /usr/bin/awk /bin/awk
ln -s /usr/bin/basename /bin/basename
ln -s /usr/bin/rpm /bin/rpm
ln -s /usr/lib/x86_64-linux-gnu /usr/lib64
if [[ $? > 0 ]]; then
    ((NUMERRS++))
    ERRS+=("Error ${ACTION}")
fi

ACTION='Creando rutas de destino de la base de datos'
printf "${ACTION}...\n" 

ACTION='Creando ruta ORACLE_HOME'
printf "${ACTION}...\n" 
mkdir -p /opt/oracle/product/12.1.0.2
if [[ $? > 0 ]]; then
    ((NUMERRS++))
    ERRS+=("Error ${ACTION}")
fi

ACTION='Creando ruta ORAINVENTORY'
printf "${ACTION}...\n" 
mkdir -p /opt/oraInventory
if [[ $? > 0 ]]; then
    ((NUMERRS++))
    ERRS+=("Error ${ACTION}")
fi

ACTION='Asignando propietario a ORACLE_BASE'
printf "${ACTION}...\n" 
chown -R oracle:dba /opt/oracle/
if [[ $? > 0 ]]; then
    ((NUMERRS++))
    ERRS+=("Error ${ACTION}")
fi

ACTION='Asignando propietario a ORAINVENTORY'
printf "${ACTION}...\n" 
chown -R oracle:dba /opt/oraInventory
if [[ $? > 0 ]]; then
    ((NUMERRS++))
    ERRS+=("Error ${ACTION}")
fi

ACTION='Instalando dependencias'
printf "${ACTION}...\n" 
apt -y install build-essential binutils libcap-dev gcc g++ libc6-dev ksh libaio-dev make libxi-dev libxtst-dev libxau-dev libxcb1-dev sysstat rpm xauth unzip rlwrap
if [[ $? > 0 ]]; then
    ((NUMERRS++))
    ERRS+=("Error ${ACTION}")
fi

ACTION='Crear SID de la base de datos'
printf "${ACTION}...\n" 
read -p 'Nombre de la base de datos: ' oracleDBname
if [[ -z ${oracleDBname} ]]; then
    ((NUMBERRS++))
    ERRS+=("Error ${ACTION}")
fi

ACTION='Creando variables del entorno para el usuario oracle'
printf "${ACTION}...\n" 
cat << EOF >> /etc/profile
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
if [[ $? > 0 ]]; then
    ((NUMERRS++))
    ERRS+=("Error ${ACTION}")
fi

ACTION='Configurando propietario de $HOME del usuario oracle'
printf "${ACTION}...\n" 
chown -R oracle. /home/oracle
if [[ $? > 0 ]]; then
    ((NUMERRS++))
    ERRS+=("Error ${ACTION}")
fi

ACTION='Creando clave de sistema para el usuario Oracle'
printf "${ACTION}...\n" 
printf 'Introducir la clave PAM de sistema para el usuario oracle: \n'
passwd oracle
if [[ $? > 0 ]]; then
    ((NUMERRS++))
    ERRS+=("Error ${ACTION}")
fi

ACTION='Descomprimiendo disco 1'
printf "${ACTION}...\n" 
ORACLEDISK1='linuxamd64_12102_database_1of2.zip'
unzip $ORACLEDISK1
if [[ $? > 0 ]]; then
    ((WARNNUMS++))
    WARNINGS+=("Advertencia ${ACTION}")
fi

ACTION='Descomprimiendo disco 2'
printf "${ACTION}...\n" 
ORACLEDISK2='linuxamd64_12102_database_2of2.zip'
unzip $ORACLEDISK2
if [[ $? > 0 ]]; then
    ((WARNNUMS++))
    WARNINGS+=("Error ${ACTION}")
fi


ACTION='Configurando OraInventory'
printf "${ACTION}...\n" 
printf 'inventory_loc=/opt/oraInventory\ninst_group=oinstall\n' > /etc/oraInst.loc
if [[ $? > 0 ]]; then
    ((NUMERRS++))
    ERRS+=("Error ${ACTION}")
fi

ACTION='Introduciendo contraseña de la base de datos'
printf "${ACTION}...\n"
printf '(8 caracteres, al menos una mayúscula y un número)\n'
read -p 'Introduce la contraseña para la BBDD: ' oraclePassword

ACTION='Creando fichero de respuesta para la instalación de oracle12c'
printf "${ACTION}...\n" 
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
if [[ $? > 0 ]]; then
    ((NUMERRS++))
    ERRS+=("Error ${ACTION}")
fi


comprobarErrores
NUMERRS=0
ERRS=()

comprobarWarnings
WARNNUMS=0
WARNINGS=()

set -e

ACTION='Instalando ejecutables de la base de datos'
printf "${ACTION}...\n" 
if [[ ! -f ${currentdir}/database/runInstaller ]]; then
    printf 'No se puede seguir, falta el fichero de instalción runInstaler\n'
    Salir
else
    sudo -i -u oracle ${currentdir}/database/runInstaller -waitforcompletion -silent -showProgress -responseFile ${currentdir}/dbresponsefile.rsp
    /opt/oraInventory/orainstRoot.sh
    /opt/oracle/product/12.1.0.2/db_home_1/root.sh
fi

ACTION='Configurando passwords'
printf "${ACTION}...\n" 
cat << EOF > cfgrsp.properties
oracle.assistants.server|S_SYSPASSWORD=${oraclePassword}
oracle.assistants.server|S_SYSTEMPASSWORD=${oraclePassword}
oracle.assistants.server|S_SYSMANPASSWORD=${oraclePassword}
oracle.assistants.server|S_DBSNMPPASSWORD=${oraclePassword}
oracle.assistants.server|S_HOSTUSERPASSWORD=${oraclePassword}
oracle.assistants.server|S_ASMSNMPPASSWORD=${oraclePassword}
EOF

ACTION='Configurando contraseñas'
printf "${ACTION}...\n" 
sudo -i -u oracle /opt/oracle/product/12.1.0.2/db_home_1/cfgtoollogs/configToolAllCommands RESPONSE_FILE=${currentdir}/cfgrsp.properties

ACTION='Creando response file para netca'
printf "${ACTION}...\n" 
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

set +e

ACTION='Descomprimiendo e instalando Client Basic'
printf "${ACTION}...\n" 
CLIENTBASIC='instantclient-basic-linux.x64-12.1.0.2.0.zip'
sudo -i -u oracle unzip ${currentdir}/${CLIENTBASIC} -d /opt/oracle
if [[ $? > 0 ]]; then
    ((NUMERRS++))
    ERRS+=("Error ${ACTION}")
fi

ACTION='Descomprimiendo SQLPlus'
printf "${ACTION}...\n" 
CLIENTSQL='instantclient-sqlplus-linux.x64-12.1.0.2.0.zip'
sudo -i -u oracle unzip ${currentdir}/${CLIENTSQL} -d /opt/oracle
if [[ $? > 0 ]]; then
    ((NUMERRS++))
    ERRS+=("Error ${ACTION}")
fi

comprobarErrores
NUMERRS=0
ERRS=()

sudo -i -u oracle ln -s /opt/oracle/instantclient_12_1/libclntsh.so{.12.1,}
sudo -i -u oracle ln -s /opt/oracle/instantclient_12_1/libocci.so{.12.1,}
