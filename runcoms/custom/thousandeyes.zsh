
# Tomcat setup
export CATALINA_OPTS="-Xmx4500m -Djava.awt.headless=true"

# ArgoCD aliases
alias argo-stg="argocd login --grpc-web --sso argocd.int-svc.eks1.stg.sfo2.1keyes.net"
alias argo-prod="argocd login --grpc-web --sso argocd.int-svc.eks1.prd.sfo2.1keyes.net"
alias argo="argocd --grpc-web"

# Teleport aliases and functions
# Taken from
# https://thousandeyes.atlassian.net/wiki/spaces/OPS/pages/4676328384/Teleport+Access+to+Kubernetes+Clusters
# https://thousandeyes.atlassian.net/wiki/spaces/FEDRAMP/pages/5164302356/FedRAMP+Teleport+Access
alias teleport-prd="tsh login --proxy=enterprise.teleport.prd.1keyes.com"
alias teleport-stg="tsh login --proxy=enterprise.teleport.stg.1keyes.com"
alias teleport-fr-prd="tsh login --proxy=enterprise.teleport.prd.us1.1keyes.org"
alias teleport-fr-stg="tsh login --proxy=enterprise.teleport.stg.us1.1keyes.org"
alias teleport-db-login="tsh db login --db-user=iam-rouser"
