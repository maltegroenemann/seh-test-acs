# Scenaro 1: constant lambda
# the compression of the price is constant throughout
x <- rnorm(1000)
y_star <- x + rnorm(1000, sd = 0.1)     # true log-price
lambda <- 0.7
y_obs <- lambda * y_star                 # compressed self-assessed value

summary(lm(y_star ~ x))   # beta ~ 1
summary(lm(y_obs  ~ x))   # beta ~ 0.7 -> attenuated, matches intuition


# Scenario 2: variable lambda (more realistic)
# the difference is larger at the extremes
x_star <- rnorm(1000)
y_star <- x_star + rnorm(1000, sd = 0.1)   # true price

mu <- mean(y_star)
lambda <- 0.5 + 0.5 * exp(-0.8 * abs(y_star - mu))  # near 1 at center, drops at tails
y_obs <- mu + lambda * (y_star - mu)                # compressed self-assessed price

plot(y_star, y_obs); abline(0, 1, col = "red")

summary(lm(y_star ~ x_star))   # true beta ~ 1
summary(lm(y_obs  ~ x_star))   # attenuated beta, < 1
