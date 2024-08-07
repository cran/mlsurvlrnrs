## ----setup--------------------------------------------------------------------
# nolint start
library(mlexperiments)
library(mlsurvlrnrs)


## -----------------------------------------------------------------------------
dataset <- survival::colon |>
  data.table::as.data.table() |>
  na.omit()
dataset <- dataset[get("etype") == 2, ]

surv_cols <- c("status", "time", "rx")
feature_cols <- colnames(dataset)[3:(ncol(dataset) - 1)]


## -----------------------------------------------------------------------------
seed <- 123
if (isTRUE(as.logical(Sys.getenv("_R_CHECK_LIMIT_CORES_")))) {
  # on cran
  ncores <- 2L
} else {
  ncores <- ifelse(
    test = parallel::detectCores() > 4,
    yes = 4L,
    no = ifelse(
      test = parallel::detectCores() < 2L,
      yes = 1L,
      no = parallel::detectCores()
    )
  )
}
options("mlexperiments.bayesian.max_init" = 10L)
options("mlexperiments.optim.xgb.nrounds" = 100L)
options("mlexperiments.optim.xgb.early_stopping_rounds" = 10L)


## -----------------------------------------------------------------------------
split_vector <- splitTools::multi_strata(
  df = dataset[, .SD, .SDcols = surv_cols],
  strategy = "kmeans",
  k = 4
)

data_split <- splitTools::partition(
  y = split_vector,
  p = c(train = 0.7, test = 0.3),
  type = "stratified",
  seed = seed
)

train_x <- model.matrix(
  ~ -1 + .,
  dataset[
    data_split$train, .SD, .SDcols = setdiff(feature_cols, surv_cols[1:2])
  ]
)
train_y <- survival::Surv(
  event = (dataset[data_split$train, get("status")] |>
             as.character() |>
             as.integer()),
  time = dataset[data_split$train, get("time")],
  type = "right"
)
split_vector_train <- splitTools::multi_strata(
  df = dataset[data_split$train, .SD, .SDcols = surv_cols],
  strategy = "kmeans",
  k = 4
)


test_x <- model.matrix(
  ~ -1 + .,
  dataset[data_split$test, .SD, .SDcols = setdiff(feature_cols, surv_cols[1:2])]
)
test_y <- survival::Surv(
  event = (dataset[data_split$test, get("status")] |>
             as.character() |>
             as.integer()),
  time = dataset[data_split$test, get("time")],
  type = "right"
)


## -----------------------------------------------------------------------------
fold_list <- splitTools::create_folds(
  y = split_vector_train,
  k = 3,
  type = "stratified",
  seed = seed
)


## -----------------------------------------------------------------------------
# required learner arguments, not optimized
learner_args <- list(
  objective = "survival:cox",
  eval_metric = "cox-nloglik"
)

# set arguments for predict function and performance metric,
# required for mlexperiments::MLCrossValidation and
# mlexperiments::MLNestedCV
predict_args <- NULL
performance_metric <- c_index
performance_metric_args <- NULL
return_models <- FALSE

# required for grid search and initialization of bayesian optimization
parameter_grid <- expand.grid(
  subsample = seq(0.6, 1, .2),
  colsample_bytree = seq(0.6, 1, .2),
  min_child_weight = seq(1, 5, 4),
  learning_rate = seq(0.1, 0.2, 0.1),
  max_depth = seq(1, 5, 4)
)
# reduce to a maximum of 10 rows
if (nrow(parameter_grid) > 10) {
  set.seed(123)
  sample_rows <- sample(seq_len(nrow(parameter_grid)), 10, FALSE)
  parameter_grid <- kdry::mlh_subset(parameter_grid, sample_rows)
}

# required for bayesian optimization
parameter_bounds <- list(
  subsample = c(0.2, 1),
  colsample_bytree = c(0.2, 1),
  min_child_weight = c(1L, 10L),
  learning_rate = c(0.1, 0.2),
  max_depth =  c(1L, 10L)
)
optim_args <- list(
  iters.n = ncores,
  kappa = 3.5,
  acq = "ucb"
)


## -----------------------------------------------------------------------------
tuner <- mlexperiments::MLTuneParameters$new(
  learner = LearnerSurvXgboostCox$new(
    metric_optimization_higher_better = FALSE
  ),
  strategy = "grid",
  ncores = ncores,
  seed = seed
)

tuner$parameter_grid <- parameter_grid
tuner$learner_args <- learner_args
tuner$split_type <- "stratified"
tuner$split_vector <- split_vector_train

tuner$set_data(
  x = train_x,
  y = train_y
)

tuner_results_grid <- tuner$execute(k = 3)
#> 
#> Parameter settings [==============================================================================================================>----------------------------] 8/10 ( 80%)
#> Parameter settings [============================================================================================================================>--------------] 9/10 ( 90%)
#> Parameter settings [==========================================================================================================================================] 10/10 (100%)                                                                                                                                                                             

head(tuner_results_grid)
#>    setting_id metric_optim_mean nrounds subsample colsample_bytree min_child_weight learning_rate max_depth    objective eval_metric
#> 1:          1          4.866125      26       0.6              0.8                5           0.2         1 survival:cox cox-nloglik
#> 2:          2          4.896370      14       1.0              0.8                5           0.1         5 survival:cox cox-nloglik
#> 3:          3          4.860956      72       0.8              0.8                5           0.1         1 survival:cox cox-nloglik
#> 4:          4          4.867604       6       0.6              0.8                5           0.2         5 survival:cox cox-nloglik
#> 5:          5          4.893917      14       1.0              0.8                1           0.1         5 survival:cox cox-nloglik
#> 6:          6          4.883471      13       0.8              0.8                5           0.1         5 survival:cox cox-nloglik


## -----------------------------------------------------------------------------
tuner <- mlexperiments::MLTuneParameters$new(
  learner = LearnerSurvXgboostCox$new(
    metric_optimization_higher_better = FALSE
  ),
  strategy = "bayesian",
  ncores = ncores,
  seed = seed
)

tuner$parameter_grid <- parameter_grid
tuner$parameter_bounds <- parameter_bounds

tuner$learner_args <- learner_args
tuner$optim_args <- optim_args

tuner$split_type <- "stratified"
tuner$split_vector <- split_vector_train

tuner$set_data(
  x = train_x,
  y = train_y
)

tuner_results_bayesian <- tuner$execute(k = 3)
#> 
#> Registering parallel backend using 4 cores.

head(tuner_results_bayesian)
#>    Epoch setting_id subsample colsample_bytree min_child_weight learning_rate max_depth gpUtility acqOptimum inBounds Elapsed     Score metric_optim_mean nrounds errorMessage
#> 1:     0          1       0.6              0.8                5           0.2         1        NA      FALSE     TRUE   1.792 -4.867594          4.867594      22           NA
#> 2:     0          2       1.0              0.8                5           0.1         5        NA      FALSE     TRUE   1.826 -4.901912          4.901912      12           NA
#> 3:     0          3       0.8              0.8                5           0.1         1        NA      FALSE     TRUE   1.833 -4.874152          4.874152      48           NA
#> 4:     0          4       0.6              0.8                5           0.2         5        NA      FALSE     TRUE   1.836 -4.870687          4.870687       5           NA
#> 5:     0          5       1.0              0.8                1           0.1         5        NA      FALSE     TRUE   0.813 -4.883240          4.883240      14           NA
#> 6:     0          6       0.8              0.8                5           0.1         5        NA      FALSE     TRUE   0.861 -4.895220          4.895220      13           NA
#>       objective eval_metric
#> 1: survival:cox cox-nloglik
#> 2: survival:cox cox-nloglik
#> 3: survival:cox cox-nloglik
#> 4: survival:cox cox-nloglik
#> 5: survival:cox cox-nloglik
#> 6: survival:cox cox-nloglik


## -----------------------------------------------------------------------------
validator <- mlexperiments::MLCrossValidation$new(
  learner = LearnerSurvXgboostCox$new(
    metric_optimization_higher_better = FALSE
  ),
  fold_list = fold_list,
  ncores = ncores,
  seed = seed
)

validator$learner_args <- tuner$results$best.setting[-1]

validator$predict_args <- predict_args
validator$performance_metric <- performance_metric
validator$performance_metric_args <- performance_metric_args
validator$return_models <- return_models

validator$set_data(
  x = train_x,
  y = train_y
)

validator_results <- validator$execute()
#> 
#> CV fold: Fold1
#> 
#> CV fold: Fold2
#> 
#> CV fold: Fold3

head(validator_results)
#>     fold performance subsample colsample_bytree min_child_weight learning_rate max_depth nrounds    objective eval_metric
#> 1: Fold1   0.6433838 0.3015909        0.5804647                1           0.2         1      27 survival:cox cox-nloglik
#> 2: Fold2   0.6979611 0.3015909        0.5804647                1           0.2         1      27 survival:cox cox-nloglik
#> 3: Fold3   0.6536441 0.3015909        0.5804647                1           0.2         1      27 survival:cox cox-nloglik


## -----------------------------------------------------------------------------
validator <- mlexperiments::MLNestedCV$new(
  learner = LearnerSurvXgboostCox$new(
    metric_optimization_higher_better = FALSE
  ),
  strategy = "grid",
  fold_list = fold_list,
  k_tuning = 3L,
  ncores = ncores,
  seed = seed
)

validator$parameter_grid <- parameter_grid
validator$learner_args <- learner_args
validator$split_type <- "stratified"
validator$split_vector <- split_vector_train

validator$predict_args <- predict_args
validator$performance_metric <- performance_metric
validator$performance_metric_args <- performance_metric_args
validator$return_models <- return_models

validator$set_data(
  x = train_x,
  y = train_y
)

validator_results <- validator$execute()
#> 
#> CV fold: Fold1
#> 
#> Parameter settings [==============================================================================================================>----------------------------] 8/10 ( 80%)
#> Parameter settings [============================================================================================================================>--------------] 9/10 ( 90%)
#> Parameter settings [==========================================================================================================================================] 10/10 (100%)                                                                                                                                                                             
#> CV fold: Fold2
#> CV progress [=================================================================================================>-------------------------------------------------] 2/3 ( 67%)
#> 
#> Parameter settings [=====================================================================>---------------------------------------------------------------------] 5/10 ( 50%)
#> Parameter settings [==================================================================================>--------------------------------------------------------] 6/10 ( 60%)
#> Parameter settings [================================================================================================>------------------------------------------] 7/10 ( 70%)
#> Parameter settings [==============================================================================================================>----------------------------] 8/10 ( 80%)
#> Parameter settings [============================================================================================================================>--------------] 9/10 ( 90%)
#> Parameter settings [==========================================================================================================================================] 10/10 (100%)                                                                                                                                                                             
#> CV fold: Fold3
#> CV progress [===================================================================================================================================================] 3/3 (100%)
#>                                                                                                                                                                              
#> Parameter settings [=======================================================>-----------------------------------------------------------------------------------] 4/10 ( 40%)
#> Parameter settings [=====================================================================>---------------------------------------------------------------------] 5/10 ( 50%)
#> Parameter settings [==================================================================================>--------------------------------------------------------] 6/10 ( 60%)
#> Parameter settings [================================================================================================>------------------------------------------] 7/10 ( 70%)
#> Parameter settings [==============================================================================================================>----------------------------] 8/10 ( 80%)
#> Parameter settings [============================================================================================================================>--------------] 9/10 ( 90%)
#> Parameter settings [==========================================================================================================================================] 10/10 (100%)                                                                                                                                                                             

head(validator_results)
#>     fold performance nrounds subsample colsample_bytree min_child_weight learning_rate max_depth    objective eval_metric
#> 1: Fold1   0.6355074      47       0.6              1.0                1           0.2         1 survival:cox cox-nloglik
#> 2: Fold2   0.6699094      13       0.8              0.8                5           0.1         5 survival:cox cox-nloglik
#> 3: Fold3   0.6832026      20       0.6              0.8                5           0.2         1 survival:cox cox-nloglik


## -----------------------------------------------------------------------------
validator <- mlexperiments::MLNestedCV$new(
  learner = LearnerSurvXgboostCox$new(
    metric_optimization_higher_better = FALSE
  ),
  strategy = "bayesian",
  fold_list = fold_list,
  k_tuning = 3L,
  ncores = ncores,
  seed = 312
)

validator$parameter_grid <- parameter_grid
validator$learner_args <- learner_args
validator$split_type <- "stratified"
validator$split_vector <- split_vector_train


validator$parameter_bounds <- parameter_bounds
validator$optim_args <- optim_args

validator$predict_args <- predict_args
validator$performance_metric <- performance_metric
validator$performance_metric_args <- performance_metric_args
validator$return_models <- TRUE

validator$set_data(
  x = train_x,
  y = train_y
)

validator_results <- validator$execute()
#> 
#> CV fold: Fold1
#> 
#> Registering parallel backend using 4 cores.
#> 
#> CV fold: Fold2
#> CV progress [=================================================================================================>-------------------------------------------------] 2/3 ( 67%)
#> 
#> Registering parallel backend using 4 cores.
#> 
#> CV fold: Fold3
#> CV progress [===================================================================================================================================================] 3/3 (100%)
#>                                                                                                                                                                              
#> Registering parallel backend using 4 cores.

head(validator_results)
#>     fold performance subsample colsample_bytree min_child_weight learning_rate max_depth nrounds    objective eval_metric
#> 1: Fold1   0.6420432 0.6394793        0.9881643                4     0.1268116         1      53 survival:cox cox-nloglik
#> 2: Fold2   0.6563499 1.0000000        1.0000000                5     0.1000000         5      11 survival:cox cox-nloglik
#> 3: Fold3   0.6573680 0.7495501        0.4383327                7     0.1000000         5      20 survival:cox cox-nloglik


## -----------------------------------------------------------------------------
preds_xgboost <- mlexperiments::predictions(
  object = validator,
  newdata = test_x
)


## -----------------------------------------------------------------------------
perf_xgboost <- mlexperiments::performance(
  object = validator,
  prediction_results = preds_xgboost,
  y_ground_truth = test_y
)
perf_xgboost
#>    model performance
#> 1: Fold1   0.6384856
#> 2: Fold2   0.6118066
#> 3: Fold3   0.6356952


## ----include=FALSE------------------------------------------------------------
# nolint end

