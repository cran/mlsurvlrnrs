% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/learner_surv_glmnet_cox.R
\name{LearnerSurvGlmnetCox}
\alias{LearnerSurvGlmnetCox}
\title{R6 Class to construct a Glmnet survival learner for Cox regression}
\description{
The \code{LearnerSurvGlmnetCox} class is the interface to perform a Cox
regression with the \code{glmnet} R package for use with the \code{mlexperiments}
package.
}
\details{
Optimization metric: C-index
Can be used with
\itemize{
\item \link[mlexperiments:MLTuneParameters]{mlexperiments::MLTuneParameters}
\item \link[mlexperiments:MLCrossValidation]{mlexperiments::MLCrossValidation}
\item \link[mlexperiments:MLNestedCV]{mlexperiments::MLNestedCV}
}
}
\examples{
# survival analysis

dataset <- survival::colon |>
  data.table::as.data.table() |>
  na.omit()
dataset <- dataset[get("etype") == 2, ]

seed <- 123
surv_cols <- c("status", "time", "rx")

feature_cols <- colnames(dataset)[3:(ncol(dataset) - 1)]

param_list_glmnet <- expand.grid(
  alpha = seq(0, 1, .2)
)

ncores <- 2L

split_vector <- splitTools::multi_strata(
  df = dataset[, .SD, .SDcols = surv_cols],
  strategy = "kmeans",
  k = 4
)

train_x <- model.matrix(
  ~ -1 + .,
  dataset[, .SD, .SDcols = setdiff(feature_cols, surv_cols[1:2])]
)
train_y <- survival::Surv(
  event = (dataset[, get("status")] |>
             as.character() |>
             as.integer()),
  time = dataset[, get("time")],
  type = "right"
)


fold_list <- splitTools::create_folds(
  y = split_vector,
  k = 3,
  type = "stratified",
  seed = seed
)

surv_glmnet_cox_optimizer <- mlexperiments::MLCrossValidation$new(
  learner = LearnerSurvGlmnetCox$new(),
  fold_list = fold_list,
  ncores = ncores,
  seed = seed
)
surv_glmnet_cox_optimizer$learner_args <- list(
  alpha = 0.8,
  lambda = 0.002
)
surv_glmnet_cox_optimizer$performance_metric <- c_index

# set data
surv_glmnet_cox_optimizer$set_data(
  x = train_x,
  y = train_y
)

surv_glmnet_cox_optimizer$execute()

## ------------------------------------------------
## Method `LearnerSurvGlmnetCox$new`
## ------------------------------------------------

LearnerSurvGlmnetCox$new()

}
\seealso{
\code{\link[glmnet:glmnet]{glmnet::glmnet()}}, \code{\link[glmnet:cv.glmnet]{glmnet::cv.glmnet()}}
}
\section{Super class}{
\code{\link[mlexperiments:MLLearnerBase]{mlexperiments::MLLearnerBase}} -> \code{LearnerSurvGlmnetCox}
}
\section{Methods}{
\subsection{Public methods}{
\itemize{
\item \href{#method-LearnerSurvGlmnetCox-new}{\code{LearnerSurvGlmnetCox$new()}}
\item \href{#method-LearnerSurvGlmnetCox-clone}{\code{LearnerSurvGlmnetCox$clone()}}
}
}
\if{html}{\out{
<details open><summary>Inherited methods</summary>
<ul>
<li><span class="pkg-link" data-pkg="mlexperiments" data-topic="MLLearnerBase" data-id="bayesian_scoring_function"><a href='../../mlexperiments/html/MLLearnerBase.html#method-MLLearnerBase-bayesian_scoring_function'><code>mlexperiments::MLLearnerBase$bayesian_scoring_function()</code></a></span></li>
<li><span class="pkg-link" data-pkg="mlexperiments" data-topic="MLLearnerBase" data-id="cross_validation"><a href='../../mlexperiments/html/MLLearnerBase.html#method-MLLearnerBase-cross_validation'><code>mlexperiments::MLLearnerBase$cross_validation()</code></a></span></li>
<li><span class="pkg-link" data-pkg="mlexperiments" data-topic="MLLearnerBase" data-id="fit"><a href='../../mlexperiments/html/MLLearnerBase.html#method-MLLearnerBase-fit'><code>mlexperiments::MLLearnerBase$fit()</code></a></span></li>
<li><span class="pkg-link" data-pkg="mlexperiments" data-topic="MLLearnerBase" data-id="predict"><a href='../../mlexperiments/html/MLLearnerBase.html#method-MLLearnerBase-predict'><code>mlexperiments::MLLearnerBase$predict()</code></a></span></li>
</ul>
</details>
}}
\if{html}{\out{<hr>}}
\if{html}{\out{<a id="method-LearnerSurvGlmnetCox-new"></a>}}
\if{latex}{\out{\hypertarget{method-LearnerSurvGlmnetCox-new}{}}}
\subsection{Method \code{new()}}{
Create a new \code{LearnerSurvGlmnetCox} object.
\subsection{Usage}{
\if{html}{\out{<div class="r">}}\preformatted{LearnerSurvGlmnetCox$new()}\if{html}{\out{</div>}}
}

\subsection{Returns}{
A new \code{LearnerSurvGlmnetCox} R6 object.
}
\subsection{Examples}{
\if{html}{\out{<div class="r example copy">}}
\preformatted{LearnerSurvGlmnetCox$new()

}
\if{html}{\out{</div>}}

}

}
\if{html}{\out{<hr>}}
\if{html}{\out{<a id="method-LearnerSurvGlmnetCox-clone"></a>}}
\if{latex}{\out{\hypertarget{method-LearnerSurvGlmnetCox-clone}{}}}
\subsection{Method \code{clone()}}{
The objects of this class are cloneable with this method.
\subsection{Usage}{
\if{html}{\out{<div class="r">}}\preformatted{LearnerSurvGlmnetCox$clone(deep = FALSE)}\if{html}{\out{</div>}}
}

\subsection{Arguments}{
\if{html}{\out{<div class="arguments">}}
\describe{
\item{\code{deep}}{Whether to make a deep clone.}
}
\if{html}{\out{</div>}}
}
}
}
