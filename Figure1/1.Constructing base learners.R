library(data.table)
library(tibble)
library(survival)
library(randomForestSRC)
library(survivalsvm)
library(gbm)
library(caret)
library(abess)
library(glmnet)
library(e1071)
library(kknn)
library(qs)
library(doParallel)
cl <- makePSOCKcluster(16)
registerDoParallel(cl)
trainset <- read.csv("dat.csv",header = T,row.names = 1,sep = ",") # Read the sample file
trainset <- trainset[,-c(2,3)]
trainset[,-1] <- log2(trainset[,-1]+1)
trainset <- trainset[!is.na(trainset$res),]
###ABESS algorithm for feature selection
abess_fit <- abess(trainset[,-1], trainset$res)
key_gene <- extract(abess_fit, 5)[4][1]$support.vars
trainset <- trainset[,c("res",key_gene)]
###Constructing base learners
riskscore <- list()
riskscore[["id"]] <- rownames(trainset)
riskscore[["res"]] <- trainset$res
####ERN
alpha <- c(0,0.2,0.4,0.6,0.8,1.0)
train_control <- trainControl(method = "repeatedcv", 
                              number = 10, 
                              repeats = 5, 
                              verboseIter = FALSE,
                              sampling = "smote")
x <- model.matrix( res~ ., trainset)[, -1]
y <- as.factor(trainset$res)

for (i in alpha  ) {
  
  model <- train(
    x, y,
    method = "glmnet",
    tuneGrid = expand.grid(alpha = i, lambda=seq(0.001, 0.1, length=100)),
    trControl = train_control
  )
  
  lambda <- model[["bestTune"]][["lambda"]]
  id <- paste("ERN_",which(i==alpha))
  riskscore[[id]] <- predict(model ,newdata =  model.matrix( res~ ., trainset)[, -1],lambda=lambda,type = "prob")[,2]
  ern_fit <- list()
  ern_fit [["fit"]] <- model
  ern_fit[["lambda"]] <- lambda 
  
  saveRDS(ern_fit ,paste0(id,".rds"))
}


###RF
depth <- c(3,5,10 ,20)
ntree <- c(200, 500, 800 ,1200)
for (i in depth ) {for(yy in ntree ){
  model <- train(
    x, y,
    method = "rf",
    trControl = train_control,
    ntree=yy,
    depth=i
  )
  id <- paste("RSF_",which(i==depth)*4-(4-which(yy==ntree)))
  riskscore[[id]] <- predict(model ,newdata =  model.matrix( res~ ., trainset)[, -1],type = "prob")[,2]
  saveRDS(model ,paste0(id,".rds"))
  
}
}
####svmLinear
parm = c(1, 10, 100, 1000)
kernel = c("svmLinear", "svmRadial", "svmPoly")

####svmRadial

for (i in parm  ) {
  model <- train(
    x, y,
    method = "svmRadial",
    trControl = train_control,
    tuneGrid = expand.grid(sigma = seq(0.001, 0.1, length = 10),
                           C =i)
  )
  sigma=model[["bestTune"]][["sigma"]]
  svm_fit <- list()
  svm_fit [["fit"]] <- model
  svm_fit[["sigma"]] <- sigma
  id <- paste("svmRadial_",which(i==parm ))
  riskscore[[id]] <- as.numeric(predict(model ,newdata =  model.matrix( res~ ., trainset)[, -1],type = "raw"))
  saveRDS(model ,paste0(id,".rds"))
  
}

####svmLinear
for (i in parm  ) {
  model <- train(
    x, y,
    method = "svmLinear",
    trControl = train_control,
    tuneGrid = expand.grid(
      C=i)
  )
  
  id <- paste("svmLinear_",which(i==parm ))
  riskscore[[id]] <- as.numeric(predict(model ,newdata =  model.matrix( res~ ., trainset)[, -1],type = "raw"))
  saveRDS(model ,paste0(id,".rds"))
  
}
####svmPoly

for (i in parm  ) {
  model <- train(
    x, y,
    method = "svmPoly",
    trControl = train_control,
    tuneGrid = expand.grid(degree=3, scale=1,
                           C=i)
  )
  
  id <- paste("svmPoly_",which(i==parm ))
  riskscore[[id]] <- as.numeric(predict(model ,newdata =  model.matrix( res~ ., trainset)[, -1],type = "raw"))
  saveRDS(model ,paste0(id,".rds"))
  
}
################KNN
k = c(3, 5, 7, 9)
kernel = c("optimal", "rank", "rectangular", "triangular")

for (i in k  ) { for(yy in kernel){
  model <- train(
    x, y,
    method = "kknn",
    trControl = train_control,
    tuneGrid = expand.grid(kmax=i,distance = c(1),kernel =yy)
  )
  id <- paste("KNN_",which(i==k)*4-(4-which(yy==kernel)))
  riskscore[[id]] <- as.numeric(predict(model ,newdata =  model.matrix( res~ ., trainset)[, -1],type = "prob")[,2])
  saveRDS(model ,paste0(id,".rds"))
  
}
}
###Saving the risk scores of individual gene learners
saveRDS(riskscore,"base_learners.rds")


