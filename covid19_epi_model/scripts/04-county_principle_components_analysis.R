# ------------------------------------------------------------------------------
# Title: Principle components of RWJ, CDC, and CMS variables
# Author: Sarah McGough; Modularized by Ryan Gan
# Purpose: Runs principle components of RWJ variables for study fips
# ------------------------------------------------------------------------------

# library
library(tidyverse)
library(yaml) # to load config file
library(factoextra) # pca package
library(corrplot) # correlation plots

# Read yaml config file --------------------------------------------------------
config <- read_yaml('./scripts/config.yaml')
rucc_code <- 3

counties_df <- read_csv('../covid-drivers/data/raw/counties_05-26.csv') %>%
  select('FIPS', 'Rural-urban_Continuum Code_2013') %>%
  rename(fips = FIPS, rucc = 'Rural-urban_Continuum Code_2013')

# Read in county fips data and make some descriptive names for study fips ------
state_county_fips <- read_csv('./data/source_data/county_fips.csv') %>%
  left_join(counties_df, by = 'fips') %>% 
  # limit to study fips
  # filter(fips %in% config$study_fips) %>% 
  filter(rucc == rucc_code) %>% 
  left_join(
    rename(
      # get state abbreviations
      data.frame(state.name, state.abb), 
      # rename
      state = state.name, 
      state_abb = state.abb),
    by = 'state') %>% 
  mutate(
    metro_area = fips
  ) %>%
  # mutate(
  #   metro_area = case_when(
  #     state == "Michigan" ~ "Detroit", 
  #     state == "Louisiana" ~ "New Orleans",
  #     state == "Washington"~ "Seattle",
  #     state == "Indiana" | state == "Illinois" ~ "Chicago",
  #     state == "New York" ~ "New York City",
  #     (state == "California" & 
  #        county == 'Los Angeles County' | county == "Orange County") ~ "Los Angeles",
  #     TRUE ~ "San Francisco"
  #   )
  # ) %>%
  mutate(
    metro_state_county = paste(metro_area,county,state_abb,sep=", ")
  )

# Read in time series data -----------------------------------------------------
# Note this data has RWJ, CDC, and CMS county data, plus aggregations for NYC
# NOTE that you must run 02-make_nyt_time_series_county.R first to get master_ts object

# read in time series to run pc on
master_ts <- read_csv(
  file = './data/03-nyt_us_county_timeseries_daily.csv',
  col_types = cols(
      'trips_count' = col_double(),
      'trips_count_baseline' = col_double(),
      'trips_count_pct_change' = col_double(),
      'trips_count_per_capita' = col_double(),
      'trips_count_log' = col_double(),
      'trips_count_per_capita_log' = col_double()
    )
  )

rwj_nyt <- master_ts %>% 
  # filter to study counties
  filter(fips %in% state_county_fips$fips) %>%
  # filter(fips %in% config$study_fips) %>% 
  # keep only variables we want to look at in the pca
  select(fips, config$pca_variables$vars) %>% 
  # single observation
  group_by(fips) %>%
  slice(1) %>% 
  # set fips as rowname to run pca only on ses vars
  column_to_rownames(var = 'fips') %>%
  drop_na()

# Principle components analysis ------------------------------------------------

# run pca
pca_rwj_nyt <- prcomp(rwj_nyt, scale = TRUE) # scale == true for standarizing

# Save dataframe
# join metro county state names for plotting
pca_df <- data.frame(pca_rwj_nyt$x) %>% 
  rownames_to_column(var = 'fips') %>% 
  left_join(state_county_fips, by = 'fips') %>% 
  select(fips, state:metro_state_county, PC1:PC24) 

# Save PC dataframe for study counties
write_csv(pca_df, './data/04-rucc_3_pca.csv')


# Results to save --------------------------------------------------------------
# save summary of pca
sink('./results/04-pca_summary-rucc_3.txt')
print(summary(pca_rwj_nyt))
sink()

# make scree plot
scree_plot <- fviz_eig(pca_rwj_nyt)
print(scree_plot)

# save scree plot in results folder naming as 03 to indicate script
ggsave(
  filename = './results/04-pca_scree-rucc_3.pdf',
  plot = scree_plot,
  width = 8, 
  height = 6,
  units = 'in'
)


# assign metro state name to pca as rowname
rownames(pca_rwj_nyt$x) <- pca_df$metro_state_county

indv_pca_plot <- fviz_pca_ind(
  pca_rwj_nyt,
  col.ind = "cos2", # Color by the quality of representation
  gradient.cols = c("#00AFBB", "#E7B800", "#FC4E07"),
  repel = TRUE
  )

# save ind plot
ggsave(
  filename = './results/04-pca_individual-rucc_3.pdf',
  plot = indv_pca_plot,
  width = 8, 
  height = 6,
  units = 'in'
)

# variable contribution
var_pca_plot <- fviz_pca_var(
  pca_rwj_nyt,
  col.var = "contrib", # Color by contributions to the PC
  gradient.cols = c("#00AFBB", "#E7B800", "#FC4E07"),
  repel = TRUE     # Avoid text overlapping
  )

# save contribution plot
ggsave(
  filename = './results/04-pca_variable_contribution-rucc_3.pdf',
  plot = var_pca_plot,
  width = 8, 
  height = 6,
  units = 'in'
)


# get pca variables
pca_vars <- get_pca_var(pca_rwj_nyt)

# save corr plot
pdf(
  file = './results/04-pca_corr_plot-rucc_3.pdf'
  , width = 8
  , height = 6
)
# corr plot
corrplot(pca_vars$cos2, is.corr=FALSE)
dev.off()

# correlation between pc1-4 and original variables
pc_original_vars_cor_df <- cor(rwj_nyt, pca_rwj_nyt$x)[,1:4] %>% 
  reshape2::melt() 
  

vars_pc_corr_plot <- ggplot(data = pc_original_vars_cor_df, aes(x = Var1, y = Var2)) + 
  geom_tile(aes(fill=value)) + 
  scale_fill_gradient2(low="indianred3",high="dodgerblue2") +
  xlab('Original Variables') +
  ylab('Principle Components') +
  coord_flip() +
  theme_classic() 

# save variable and principle components correlation plot
ggsave(
  filename = './results/04-pc_variable_corr_plot-rucc_3.pdf',
  plot = vars_pc_corr_plot,
  width = 8, 
  height = 6,
  units = 'in'
  )

# top 10 correlation by pc dataframe
top10_vars_df <- pc_original_vars_cor_df  %>%
  group_by(Var2) %>% 
  arrange(desc(abs(value))) %>% 
  slice(1:10) %>% 
  ungroup()
  
# top 10 plot used in manuscript
top10_plot <- ggplot(
  data = top10_vars_df, 
  aes(x = reorder(Var1, (abs(value))), y = value, fill=value)
  ) + 
  geom_bar(stat="identity") + 
  facet_wrap(~Var2, scales="free_y") + 
  coord_flip() + 
  theme_minimal() + 
  scale_fill_gradient(low="indianred3",high="dodgerblue2")


# save plot
ggsave(
  filename = './results/04-top10_pc_vars-rucc_3.pdf',
  plot = top10_plot,
  width = 8, 
  height = 6,
  units = 'in'
  )
  
top10_pc1 <- ggplot(
    data = filter(top10_vars_df, Var2=='PC1'),
    aes(reorder(Var1, (abs(value))), value, fill=value)
    ) + 
  geom_bar(stat="identity") + 
  #facet_wrap(~Var2, scales="free_y") + 
  coord_flip() + 
  theme_minimal() + 
  scale_fill_gradient(low="indianred3",high="dodgerblue2") + xlab("Variable") +
  ggtitle("Top 10 variable correlations with PC1")

# save plot
ggsave(
  filename = './results/04-top10_pc1-rucc_3.pdf',
  plot = top10_pc1,
  width = 8, 
  height = 12,
  units = 'in'
)

# Sensitivity PC Excluding NYC -------------------------------------------------
rwj_nonyc <- master_ts %>% 
  # filter to study counties
  filter(fips %in% config$study_fips) %>% 
  # filter out nyc fips of 36061
  filter(fips != '36061') %>% 
  # keep only variables we want to look at in the pca
  select(fips, config$pca_variables$vars) %>% 
  # single observation
  group_by(fips) %>%
  slice(1) %>% 
  # set fips as rowname to run pca only on ses vars
  column_to_rownames(var = 'fips')

# run pca on non-nyc fips
# run pca
pca_rwj_nonyc <- prcomp(rwj_nonyc, scale = TRUE) # scale == true for standarizing

# Save dataframe
# join metro county state names for plotting
pca_nonyc_df <- data.frame(pca_rwj_nonyc$x) %>% 
  rownames_to_column(var = 'fips') %>% 
  left_join(state_county_fips, by = 'fips') %>% 
  select(fips, state:metro_state_county, PC1:PC23) 


# Save PC dataframe for study counties
write_csv(pca_nonyc_df, './data/04-study_fips_nonyc_pca-rucc_3.csv')

# Correlation plot excluding NYC
# correlation between pc1-4 and original variables
nonyc_vars_cor_df <- cor(rwj_nonyc, pca_rwj_nonyc$x)[,1:4] %>% 
  reshape2::melt() 


nonyc_corr_plot <- ggplot(data = nonyc_vars_cor_df, aes(x = Var1, y = Var2)) + 
  geom_tile(aes(fill=value)) + 
  scale_fill_gradient2(low="indianred3",high="dodgerblue2") +
  xlab('Original Variables') +
  ylab('Principle Components') +
  coord_flip() +
  theme_classic() 


# save variable and principle components correlation plot
ggsave(
  filename = './results/04-no_nyc_pc_variable_corr_plot-rucc_3.pdf',
  plot = nonyc_corr_plot,
  width = 8, 
  height = 6,
  units = 'in'
)

# top 10 correlation by pc dataframe
top10_vars_df <- nonyc_vars_cor_df %>%
  group_by(Var2) %>% 
  arrange(desc(abs(value))) %>% 
  slice(1:10) %>% 
  ungroup()

# top 10 plot used in manuscript
nonyc_top10_plot <- ggplot(
  data = top10_vars_df, 
  aes(x = reorder(Var1, (abs(value))), y = value, fill=value)
  ) + 
  geom_bar(stat="identity") + 
  facet_wrap(~Var2, scales="free_y") + 
  xlab('Variables') +
  ylab('Values') +
  ggtitle('Exlucluding NYC: Top 10 variable contributions for principle compoenents') +
  coord_flip() + 
  theme_minimal() + 
  scale_fill_gradient(low="indianred3",high="dodgerblue2")

# save plot
# save variable and principle components correlation plot
ggsave(
  filename = './results/04-no_nyc_top10_pc_vars-rucc_3.pdf',
  plot = nonyc_top10_plot,
  width = 8, 
  height = 6,
  units = 'in'
)


