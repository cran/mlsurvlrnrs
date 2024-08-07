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
cat_vars <- c("sex", "obstruct", "perfor", "adhere", "differ", "extent",
              "surg", "node4", "rx")


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
learner_args <- NULL

# set arguments for predict function and performance metric,
# required for mlexperiments::MLCrossValidation and
# mlexperiments::MLNestedCV
predict_args <- NULL
performance_metric <- c_index
performance_metric_args <- NULL
return_models <- FALSE

# required for grid search and initialization of bayesian optimization
parameter_grid <- expand.grid(
  alpha = seq(0, 1, 0.05)
)
# reduce to a maximum of 10 rows
if (nrow(parameter_grid) > 10) {
  set.seed(123)
  sample_rows <- sample(seq_len(nrow(parameter_grid)), 10, FALSE)
  parameter_grid <- kdry::mlh_subset(parameter_grid, sample_rows)
}

# required for bayesian optimization
parameter_bounds <- list(
  alpha = c(0., 1.)
)
optim_args <- list(
  iters.n = ncores,
  kappa = 3.5,
  acq = "ucb"
)


## -----------------------------------------------------------------------------
tuner <- mlexperiments::MLTuneParameters$new(
  learner = LearnerSurvGlmnetCox$new(),
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
#> Parameter settings [===========================>---------------------------------------------------------------------------------------------------------------] 2/10 ( 20%)
#> Parameter settings [=========================================>-------------------------------------------------------------------------------------------------] 3/10 ( 30%)
#> Parameter settings [=======================================================>-----------------------------------------------------------------------------------] 4/10 ( 40%)
#> Parameter settings [=====================================================================>---------------------------------------------------------------------] 5/10 ( 50%)
#> Parameter settings [==================================================================================>--------------------------------------------------------] 6/10 ( 60%)
#> Parameter settings [================================================================================================>------------------------------------------] 7/10 ( 70%)
#> Parameter settings [==============================================================================================================>----------------------------] 8/10 ( 80%)
#> Parameter settings [============================================================================================================================>--------------] 9/10 ( 90%)
#> Parameter settings [==========================================================================================================================================] 10/10 (100%)                                                                                                                                                                             

head(tuner_results_grid)
#>    setting_id metric_optim_mean    lambda alpha
#> 1:          1         0.6420939 0.1571721  0.70
#> 2:          2         0.6473427 0.1222450  0.90
#> 3:          3         0.6420939 0.1692623  0.65
#> 4:          4         0.6503151 0.9134093  0.10
#> 5:          5         0.6448394 0.2227701  0.45
#> 6:          6         0.6516264 2.0049311  0.05


## -----------------------------------------------------------------------------
tuner <- mlexperiments::MLTuneParameters$new(
  learner = LearnerSurvGlmnetCox$new(),
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
#>    Epoch setting_id alpha gpUtility acqOptimum inBounds Elapsed     Score metric_optim_mean    lambda errorMessage
#> 1:     0          1  0.70        NA      FALSE     TRUE   1.186 0.6420939         0.6420939 0.1571721           NA
#> 2:     0          2  0.90        NA      FALSE     TRUE   1.157 0.6473427         0.6473427 0.1222450           NA
#> 3:     0          3  0.65        NA      FALSE     TRUE   1.163 0.6420939         0.6420939 0.1692623           NA
#> 4:     0          4  0.10        NA      FALSE     TRUE   1.177 0.6503151         0.6503151 0.9134093           NA
#> 5:     0          5  0.45        NA      FALSE     TRUE   0.240 0.6448394         0.6448394 0.2227701           NA
#> 6:     0          6  0.05        NA      FALSE     TRUE   0.286 0.6516264         0.6516264 2.0049311           NA


## -----------------------------------------------------------------------------
validator <- mlexperiments::MLCrossValidation$new(
  learner = LearnerSurvGlmnetCox$new(),
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
#>     fold performance      alpha   lambda
#> 1: Fold1   0.5959883 0.03836977 2.612644
#> 2: Fold2   0.6688831 0.03836977 2.612644
#> 3: Fold3   0.6899724 0.03836977 2.612644


## -----------------------------------------------------------------------------
validator <- mlexperiments::MLNestedCV$new(
  learner = LearnerSurvGlmnetCox$new(),
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
#> Parameter settings [===========================>---------------------------------------------------------------------------------------------------------------] 2/10 ( 20%)
#> Parameter settings [=========================================>-------------------------------------------------------------------------------------------------] 3/10 ( 30%)
#> Parameter settings [=======================================================>-----------------------------------------------------------------------------------] 4/10 ( 40%)
#> Parameter settings [=====================================================================>---------------------------------------------------------------------] 5/10 ( 50%)
#> Parameter settings [==================================================================================>--------------------------------------------------------] 6/10 ( 60%)
#> Parameter settings [================================================================================================>------------------------------------------] 7/10 ( 70%)
#> Parameter settings [==============================================================================================================>----------------------------] 8/10 ( 80%)
#> Parameter settings [============================================================================================================================>--------------] 9/10 ( 90%)
#> Parameter settings [==========================================================================================================================================] 10/10 (100%)                                                                                                                                                                             
#> CV fold: Fold2
#> CV progress [=================================================================================================>-------------------------------------------------] 2/3 ( 67%)
#> 
#> Parameter settings [===========================>---------------------------------------------------------------------------------------------------------------] 2/10 ( 20%)
#> Parameter settings [=========================================>-------------------------------------------------------------------------------------------------] 3/10 ( 30%)
#> Parameter settings [=======================================================>-----------------------------------------------------------------------------------] 4/10 ( 40%)
#> Parameter settings [=====================================================================>---------------------------------------------------------------------] 5/10 ( 50%)
#> Parameter settings [==================================================================================>--------------------------------------------------------] 6/10 ( 60%)
#> Parameter settings [================================================================================================>------------------------------------------] 7/10 ( 70%)
#> Parameter settings [==============================================================================================================>----------------------------] 8/10 ( 80%)
#> Parameter settings [============================================================================================================================>--------------] 9/10 ( 90%)
#> Parameter settings [==========================================================================================================================================] 10/10 (100%)                                                                                                                                                                             
#> CV fold: Fold3
#> CV progress [===================================================================================================================================================] 3/3 (100%)
#>                                                                                                                                                                              
#> Parameter settings [===========================>---------------------------------------------------------------------------------------------------------------] 2/10 ( 20%)
#> Parameter settings [=========================================>-------------------------------------------------------------------------------------------------] 3/10 ( 30%)
#> Parameter settings [=======================================================>-----------------------------------------------------------------------------------] 4/10 ( 40%)
#> Parameter settings [=====================================================================>---------------------------------------------------------------------] 5/10 ( 50%)
#> Parameter settings [==================================================================================>--------------------------------------------------------] 6/10 ( 60%)
#> Parameter settings [================================================================================================>------------------------------------------] 7/10 ( 70%)
#> Parameter settings [==============================================================================================================>----------------------------] 8/10 ( 80%)
#> Parameter settings [============================================================================================================================>--------------] 9/10 ( 90%)
#> Parameter settings [==========================================================================================================================================] 10/10 (100%)                                                                                                                                                                             

head(validator_results)
#>     fold performance    lambda alpha
#> 1: Fold1   0.5881450 1.2565031  0.05
#> 2: Fold2   0.6187568 0.4969800  0.10
#> 3: Fold3   0.6882968 0.1076019  0.05


## -----------------------------------------------------------------------------
validator <- mlexperiments::MLNestedCV$new(
  learner = LearnerSurvGlmnetCox$new(),
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
#>     fold performance       alpha      lambda
#> 1: Fold1   0.5921167 0.001528976 28.32153046
#> 2: Fold2   0.6033518 0.450000000  0.05758351
#> 3: Fold3   0.6908924 0.150000000  0.40290596


## -----------------------------------------------------------------------------
train_x_coxph <- data.matrix(
  dataset[
    data_split$train, .SD, .SDcols = setdiff(feature_cols, surv_cols[1:2])
  ]
)
test_x_coxph <- data.matrix(
  dataset[
    data_split$test, .SD, .SDcols = setdiff(feature_cols, surv_cols[1:2])
  ]
)


## -----------------------------------------------------------------------------
validator_coxph <- mlexperiments::MLCrossValidation$new(
  learner = LearnerSurvCoxPHCox$new(),
  fold_list = fold_list,
  ncores = ncores,
  seed = seed
)
validator_coxph$performance_metric <- performance_metric
validator_coxph$performance_metric_args <- performance_metric_args
validator_coxph$return_models <- TRUE
validator_coxph$set_data(
  x = train_x_coxph,
  y = train_y,
  cat_vars = cat_vars
)
validator_coxph_results <- validator_coxph$execute()
#> 
#> CV fold: Fold1
#> Parameter 'ncores' is ignored for learner 'LearnerSurvCoxPHCox'.
#> 
#> CV fold: Fold2
#> Parameter 'ncores' is ignored for learner 'LearnerSurvCoxPHCox'.
#> 
#> CV fold: Fold3
#> Parameter 'ncores' is ignored for learner 'LearnerSurvCoxPHCox'.

head(validator_coxph_results)
#>     fold performance
#> 1: Fold1   0.5895801
#> 2: Fold2   0.5992298
#> 3: Fold3   0.6732488


## -----------------------------------------------------------------------------
mlexperiments::validate_fold_equality(
  experiments = list(validator, validator_coxph)
)


## -----------------------------------------------------------------------------
preds_glmnet <- mlexperiments::predictions(
  object = validator,
  newdata = test_x
)
preds_coxph <- mlexperiments::predictions(
  object = validator_coxph,
  newdata = test_x_coxph
)


## -----------------------------------------------------------------------------
perf_glmnet <- mlexperiments::performance(
  object = validator,
  prediction_results = preds_glmnet,
  y_ground_truth = test_y
)
perf_glmnet
#>    model performance
#> 1: Fold1   0.6660022
#> 2: Fold2   0.6846061
#> 3: Fold3   0.6636560


## -----------------------------------------------------------------------------
perf_coxph <- mlexperiments::performance(
  object = validator_coxph,
  prediction_results = preds_coxph,
  y_ground_truth = test_y
)
perf_coxph
#>    model performance
#> 1: Fold1   0.6758025
#> 2: Fold2   0.6782526
#> 3: Fold3   0.6437025


## ----include=FALSE------------------------------------------------------------
# nolint end

