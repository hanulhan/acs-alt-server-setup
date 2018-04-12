JAVA_OPTS="-Xms1512M
           -Xmx1512M
           -XX:+UseConcMarkSweepGC
           -XX:+CMSIncrementalMode
           -XX:+HeapDumpOnOutOfMemoryError
           -XX:HeapDumpPath=/var/log/tomcat7/
           -Dcom.sun.management.jmxremote
           -Dcom.sun.management.jmxremote.ssl=false
           -Dcom.sun.management.jmxremote.local.only=false
           -Dcom.sun.management.jmxremote.authenticate=false
           -Dcom.sun.management.jmxremote.port=1098
           -Dcom.sun.management.jmxremote.rmi.port=1098
           -Djava.rmi.server.hostname=acs.acentic.com"

