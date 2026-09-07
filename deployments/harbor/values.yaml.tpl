expose:
  type: clusterIP
  tls:
    enabled: false
  clusterIP:
    name: harbor
    ports:
      httpPort: 80

externalURL: "__HARBOR_EXTERNAL_URL__"

existingSecretAdminPassword: harbor-admin-password
existingSecretAdminPasswordKey: HARBOR_ADMIN_PASSWORD
existingSecretSecretKey: harbor-core-secret-key

persistence:
  enabled: true
  resourcePolicy: keep

  persistentVolumeClaim:
    registry:
      storageClass: local-path
      accessMode: ReadWriteOnce
      size: 2Gi

    jobservice:
      jobLog:
        storageClass: local-path
        accessMode: ReadWriteOnce
        size: 1Gi

    database:
      storageClass: local-path
      accessMode: ReadWriteOnce
      size: 1Gi

    redis:
      storageClass: local-path
      accessMode: ReadWriteOnce
      size: 1Gi

    trivy:
      storageClass: local-path
      accessMode: ReadWriteOnce
      size: 1Gi

  imageChartStorage:
    type: filesystem

updateStrategy:
  type: Recreate

trivy:
  enabled: true
  ignoreUnfixed: false
  severity: UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL

logLevel: info
