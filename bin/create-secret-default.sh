kubectl --context secrets-default create secret generic demo \
  --from-literal username=sethvargo \
  --from-literal password=s3cr3t
