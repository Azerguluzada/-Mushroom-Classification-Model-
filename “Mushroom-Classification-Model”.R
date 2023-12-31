# AutoML Classification and Explanation of Black Box

# Import libraries & dataset ----
library(tidyverse)
library(data.table)
library(rstudioapi)
library(skimr)
library(car)
library(h2o)
library(rlang)
library(glue)
library(highcharter)
library(lime)


raw <- fread("C:/Users/User/Downloads/mushrooms.csv")

raw %>% skim()

raw$class %>% table() %>% prop.table()

raw$class <- raw$class %>% 
  factor(levels = c('e','p'),
         labels = c(1,0))
sapply(raw, class)
raw <-raw %>%
  mutate_if(is.character,as.factor) %>% 
  select_if(is.factor) %>%
  select(class,everything())
skim(raw)

func <- function(df){
  gsub("\\'","", df)
  gsub("\\'" ,"", df)
}

# --------------------------------- Modeling ----------------------------------
h2o.init()

h2o_data <- raw %>% as.h2o()


# Splitting the data ----
h2o_data <- h2o_data %>% h2o.splitFrame(ratios = 0.8, seed = 123)
train <- h2o_data[[1]]
test <- h2o_data[[2]]

target <- 'class'
features <- raw %>% select(-class) %>% names()


# Fitting h2o model ----
model <- h2o.automl(
  x = features, y = target,
  training_frame = train,
  validation_frame = test,
  leaderboard_frame = test,
  stopping_metric = "AUC", seed = 123,
  max_runtime_secs = 60)

model@leaderboard %>% as.data.frame()
model@leader 


# Predicting the Test set results ----
pred <- model@leader %>% h2o.predict(test) %>% as.data.frame()

# Threshold / Cutoff ----  
model@leader %>% 
  h2o.performance(test) %>% 
  h2o.find_threshold_by_max_metric('f1') -> treshold


# ----------------------------- Model evaluation -----------------------------

# Confusion Matrix----
model@leader %>% 
  h2o.confusionMatrix(test) %>% 
  as_tibble() %>% 
  select("0","1") %>% 
  .[1:2,] %>% t() %>% 
  fourfoldplot(conf.level = 0, color = c("red", "darkgreen"),
               main = paste("Accuracy = ",
                            round(sum(diag(.))/sum(.)*100,1),"%"))


# Area Under Curve (AUC) ----
# threshold - proqnozları o ve 1 e cevirmek ucun secilmmis optimal limit xetdir
# precision - tp/(tp+fp)
# recall    - tp/(tp+fn)
model@leader %>% 
  h2o.performance(test) %>% 
  h2o.metric() %>% 
  select(threshold,precision,recall,tpr,fpr) %>% 
  add_column(tpr_r=runif(nrow(.),min=0.001,max=1)) %>% 
  mutate(fpr_r=tpr_r) %>% 
  arrange(tpr_r,fpr_r) -> deep_metrics

model@leader %>% 
  h2o.performance(test) %>% 
  h2o.auc() %>% round(2) -> auc

highchart() %>% 
  hc_add_series(deep_metrics, "scatter", hcaes(y=tpr,x=fpr), color='green', name='TPR') %>%
  hc_add_series(deep_metrics, "line", hcaes(y=tpr_r,x=fpr_r), color='red', name='Random Guess') %>% 
  hc_add_annotation(
    labels = list(
      point = list(xAxis=0,yAxis=0,x=0.3,y=0.6),
      text = glue('AUC = {enexpr(auc)}'))
  ) %>%
  hc_title(text = "ROC Curve") %>% 
  hc_subtitle(text = "Model is performing much better than random guessing") 


# Check overfitting ----
model@leader %>%
  h2o.auc(train = T,
          valid = T,
          xval = T) %>%
  as_tibble() %>%
  round(2) %>%
  mutate(data = c('train','test','cross_val')) %>%
  mutate(gini = 2*value-1) %>%
  select(data,auc=value,gini)
