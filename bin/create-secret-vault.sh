kubectl --context secrets-vault create secret generic demo \
  --from-literal username=sethvargo \
  --from-literal password=s3cr3t
