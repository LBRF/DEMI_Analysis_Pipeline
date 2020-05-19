### Filters for cleaning tracing data before processing ###


### Import required libraries ###

library(dplyr)



# Flags extra points following unsuccessful trial end

trial_done <- function(origin_dist, timediff, params) {

  origin_radius <- params$origin_radius
  end_radius <- params$end_radius
  min_prop <- params$min_prop
  end_prop <- params$end_prop
  min_pause <- params$min_pause

  # Get proportion of tracing complete for each sample
  n_samples <- length(origin_dist)
  prop <- seq_len(n_samples) / n_samples

  # Pre-compute some metrics needed for the filter
  eligible <- prop >= min_prop
  not_first <- !is.na(lag(origin_dist))
  on_origin <- origin_dist < origin_radius
  further_from_origin <- not_first & origin_dist > lag(origin_dist)

  # Flag all samples after tracing re-enters expanded origin boundary and
  # then starts to get farther away from the origin again (i.e. misses the
  # origin), provided there aren't any remaining samples too far from origin
  entered <- not_first & on_origin & !lag(on_origin)
  on_last_segment <- rev(cumsum(rev(origin_dist > end_radius))) == 0
  returned <- cumsum(entered & on_last_segment & eligible) > 0
  missed <- cumsum(returned & further_from_origin) > 0

  # Flag all samples after tracing stops moving for a while within wider
  # threshold of origin boundary (after wider boundary is exited)
  stopped <- !is.na(lead(timediff)) & lead(timediff) > min_pause
  near_end <- prop >= end_prop
  stopped_near <- cumsum(stopped & near_end) > 0

  missed | stopped_near
}


# Flags points from touchscreen glitches

is_glitch <- function(dist, angle_diff, origin_dist, params) {

  min_dist <- params$min_dist
  min_angle_diff <- params$min_angle_diff

  # If two large consecutive jumps, and angle difference between jumps beyond
  # threshold, flag point after first jump as glitch
  eligible <- !is.na(dist) & !is.na(lead(dist)) & !is.na(lead(angle_diff))
  both_large <- dist > min_dist & lead(dist) > min_dist
  sharp_angle <- abs(lead(angle_diff)) > min_angle_diff
  angle_glitch <- eligible & both_large & sharp_angle

  # Sometimes, multiple glitches occur in a row such that the first glitch point
  # fails the angle threshold. This attempts to catch these missed points.
  before_glitch <- eligible & lead(angle_glitch)
  after_glitch <- eligible & lag(angle_glitch)
  valid <- before_glitch & !after_glitch & !is.na(angle_diff)
  pre_glitch <- valid & dist > min_dist & abs(angle_diff) > min_angle_diff

  # If first point of trial is really far from origin, flag as glitch
  start_glitch <- is.na(dist) & lead(dist) > min_dist & origin_dist > min_dist

  # If last point of trial is large jump away from origin, flag that too
  end_glitch <- is.na(lead(dist)) & (origin_dist - lag(origin_dist)) > min_dist

  angle_glitch | pre_glitch | start_glitch | end_glitch
}


# Flag points preceeding abnormal time jump within first few samples

false_start <- function(timediff, params) {

  start_samples <- params$start_samples
  min_timediff <- params$min_timediff

  # This is weirdly slow. Any idea why? It works right, at least.
  within_start <- seq_along(timediff) < start_samples
  early_gap <- within_start & lead(timediff) > min_timediff
  false_start <- rev(cumsum(rev(!is.na(early_gap) & early_gap))) > 0

  false_start
}


# Flag points likely to be due to accidental input from other part of hand

hand_noise <- function(dist, timediff, angle_diff, origin_dist, params) {

  min_sharp_turnsum <- params$min_sharp_turnsum
  max_samples <- params$max_samples
  max_timediff  <- params$max_timediff
  min_dist_a  <- params$min_dist_a
  min_dist_b  <- params$min_dist_b
  min_angle_diff  <- params$min_angle_diff
  min_end_dist  <- params$min_end_dist

  # Check whether the trial has any jumps sharp enough to indicate hand noise
  sharp_turn <- (abs(angle_diff) + abs(lead(angle_diff))) > min_sharp_turnsum
  any_sharp_jumps <- any(dist > min_dist_a & sharp_turn, na.rm = TRUE)

  # If two largest jumps meet threshold values, and number of samples
  # between them is small enough, flag those samples as hand noise
  second_largest <- sort(dist, decreasing = TRUE)[2]
  eligible <- any_sharp_jumps & !is.na(angle_diff) & timediff < max_timediff
  thresh1 <- dist > min_dist_a & abs(angle_diff) > min_angle_diff
  thresh2 <- dist > min_dist_b
  large_enough <- thresh1 | thresh2
  large_jump <- eligible & large_enough & dist >= second_largest
  jumps <- cumsum(large_jump)
  is_noise <- jumps %% 2 == 1 & max(jumps) %% 2 == 0
  is_noise <- is_noise & sum(is_noise) < max_samples

  # Check for hand noise at end of trial (large jump away from origin in
  # the last few samples)
  n_samples <- length(origin_dist)
  prop <- seq_len(n_samples) / n_samples
  end_prop <- max(2 / n_samples, (n_samples - max_samples) / n_samples)
  away_from_origin <- (origin_dist - lag(origin_dist)) > min_end_dist
  end_noise <- cumsum(prop >= end_prop & away_from_origin) > 0

  is_noise | end_noise
}


# Flag tracings likely to be accidentally incomplete

is_incomplete <- function(end_gap, samples, fig_samples, params) {

  min_end_gap <- params$min_end_gap
  min_sample_ratio <- params$min_sample_ratio

  # Apply the end-gap and sample ratio filters
  too_small <- (fig_samples / samples) > min_sample_ratio
  no_return <- end_gap > min_end_gap

  too_small | no_return
}


# Flag excessive time or distance gaps during tracings

is_gap <- function(dist, timediff, turnsum, params) {

  min_pause <- params$min_pause
  min_timegap <- params$min_timegap
  min_dist_b <- params$min_dist_b
  min_dist_c <- params$min_dist_c
  min_dist_d <- params$min_dist_d
  min_turnsum_c <- params$min_turnsum_c
  min_turnsum_d <- params$min_turnsum_d

  # Figure out which samples are eligible to be lifts based on minimum timegap
  eligible <- !is.na(dist) & timediff > min_timegap

  # Apply all four filters to the samples to catch any lifts
  lift_t <- timediff > min_pause
  lift_dt <- eligible & dist > min_dist_b
  lift_dat <- eligible & dist > min_dist_c & turnsum > min_turnsum_c
  lift_dat2 <- eligible & dist > min_dist_d & turnsum > min_turnsum_d

  lift_t | lift_dt | lift_dat | lift_dat2
}