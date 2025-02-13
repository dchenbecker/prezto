
# Tomcat setup
export CATALINA_OPTS="-Xmx4500m -Djava.awt.headless=true"

# ArgoCD aliases
alias argo-stg="argocd login --grpc-web --sso argocd.int-svc.eks1.stg.sfo2.1keyes.net"
alias argo-prod="argocd login --grpc-web --sso argocd.int-svc.eks1.prd.sfo2.1keyes.net"
alias argo="argocd --grpc-web"
