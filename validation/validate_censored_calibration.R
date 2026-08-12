# Cross-language parity check for the censored-calibration article.

library(survival)

patients <- read.csv("validation/generated/patients.csv")
points <- read.csv("validation/generated/points.csv")

data_root <- paste0(
  "https://raw.githubusercontent.com/",
  "danielegiardiello/Prediction_performance_survival/main/Data"
)
rotterdam <- read.csv(paste0(data_root, "/rotterdam.csv"))
gbsg <- read.csv(paste0(data_root, "/gbsg.csv"))

rcs_3_eval <- function(x, knots) {
  k0 <- knots[1]
  k1 <- knots[2]
  k2 <- knots[3]
  (
    pmax(x - k0, 0)^3 -
      pmax(x - k1, 0)^3 * (k2 - k0) / (k2 - k1) +
      pmax(x - k2, 0)^3 * (k1 - k0) / (k2 - k1)
  ) / (k2 - k0)^2
}

rotterdam$time <- rotterdam$rtime / 365.25
rotterdam$event <- pmax(rotterdam$recur, rotterdam$death)
death_only <- with(
  rotterdam,
  event == 1 & recur == 0 & death == 1 & rtime < dtime
)
rotterdam$time[death_only] <- rotterdam$dtime[death_only] / 365.25
gbsg$time <- gbsg$rfstime / 365.25
gbsg$event <- gbsg$status

rotterdam$size_20_50 <- as.integer(rotterdam$size == "20-50")
rotterdam$size_gt_50 <- as.integer(rotterdam$size == ">50")
gbsg$size_20_50 <- as.integer(gbsg$size > 20 & gbsg$size <= 50)
gbsg$size_gt_50 <- as.integer(gbsg$size > 50)

for (data_name in c("rotterdam", "gbsg")) {
  data <- get(data_name)
  data$grade_3 <- as.integer(data$grade == 3)
  data$nodes2 <- pmin(data$nodes, 19)
  data$nodes3 <- rcs_3_eval(data$nodes2, c(0, 1, 9))
  data$event <- ifelse(data$event == 1 & data$time > 5, 0, data$event)
  data$time <- pmin(data$time, 5)
  assign(data_name, data)
}

features <- c("size_20_50", "size_gt_50", "grade_3", "nodes2", "nodes3")
formula <- Surv(time, event) ~ size_20_50 + size_gt_50 + grade_3 + nodes2 + nodes3
r_cox <- coxph(formula, data = rotterdam, ties = "efron", x = TRUE, y = TRUE)

r_prediction_rows <- do.call(rbind, lapply(sort(unique(patients$horizon)), function(horizon) {
  fitted_survival <- survfit(r_cox, newdata = gbsg[, features], se.fit = FALSE)
  survival_at_horizon <- summary(
    fitted_survival, times = horizon, extend = TRUE
  )$surv
  data.frame(
    pid = gbsg$pid,
    horizon = horizon,
    prediction_r = 1 - as.numeric(survival_at_horizon)
  )
}))

prediction_comparison <- merge(
  patients[, c("pid", "horizon", "prediction_python")],
  r_prediction_rows,
  by = c("pid", "horizon")
)
prediction_comparison$absolute_difference <- abs(
  prediction_comparison$prediction_python - prediction_comparison$prediction_r
)

risk_from_km <- function(time, event, horizon) {
  fit <- survfit(Surv(time, event) ~ 1)
  1 - summary(fit, times = horizon, extend = TRUE)$surv
}

r_points <- do.call(
  rbind,
  lapply(split(patients, list(patients$horizon, patients$decile)), function(x) {
    data.frame(
      horizon = x$horizon[1],
      decile = x$decile[1],
      observed_risk_r = risk_from_km(x$time, x$event, x$horizon[1])
    )
  })
)

comparison <- merge(points, r_points, by = c("horizon", "decile"))
comparison$absolute_difference <- abs(
  comparison$observed_risk_rtichoke - comparison$observed_risk_r
)

stopifnot(nrow(comparison) == 50)
stopifnot(max(comparison$absolute_difference) < 1e-12)
stopifnot(nrow(prediction_comparison) == 686 * 5)
stopifnot(max(prediction_comparison$absolute_difference) < 5e-3)

cat("Validated", nrow(prediction_comparison), "individual Cox predictions.\n")
cat(
  "Maximum absolute prediction difference between lifelines and R survival:",
  format(max(prediction_comparison$absolute_difference), scientific = TRUE),
  "\n"
)
cat("Validated", nrow(comparison), "local calibration points.\n")
cat(
  "Maximum absolute difference between rtichoke and R survival::survfit:",
  format(max(comparison$absolute_difference), scientific = TRUE),
  "\n"
)
