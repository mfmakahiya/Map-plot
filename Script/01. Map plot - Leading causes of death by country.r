

rm(list=ls())
library(memisc)
library(assertthat)
library(sqldf)
library(magrittr)
library(dplyr)
library(reshape2)
library(ggplot2)
library(oz)
library(scatterpie)
library(rgdal)
library(maptools)

# Helper functions

data_prep <- function(csv_name) {
  
  import <- read.csv(paste0("./Data/", csv_name), stringsAsFactors = F)
  names(import) <- tolower(names(import))
  
  import <- import[, c("country.or.area",
                       "sex",
                       "age",
                       "cause.of.death..who.",
                       "record.type",
                       "value")]
  
  names(import) <- c("country", "sex", "age", "death_cause", "record_type", "value")
  
  assert_that(length(names(import)) == 6)
  
  return(import)
  
}

###############

perform_groupby <- function(data, sex_filter, record_filter) {
  
  #data <- import
  #sex_filter <- "Female"
  #record_filter <- "Data tabulated by year of occurrence"
  
  final_data <- data %>%
    filter (!sex == sex_filter, record_type == record_filter) %>%
    group_by(country, death_cause) %>%
    summarise(count = sum(value)) %>%
    ungroup %>%
    as.data.frame()
  
  return(final_data)
}

pivot_by_country <- function(data) {
  
  s1 = melt(data, id = c("country", "death_cause"), measure.vars = "count")
  s2 = dcast(s1, country ~ death_cause, sum)
  
  s2$Total = rowSums(s2[,2:NCOL(s2)])
  return(s2)
}


# Main Logic
death_data <- data_prep("death2014.csv")
grouped_data <- perform_groupby(death_data, "", "Data tabulated by year of occurrence") # Data tabulated by year of occurrence # Data tabulated by year of registration
grouped_data$death_cause <- gsub("*, ICD10", "", grouped_data$death_cause)
grouped_data$death_cause <- gsub("Symptoms, signs and abnormal clinical and laboratory findings, not elsewhere classified", "Abnormal clinical and lab findings", grouped_data$death_cause)


# Top 10 leading cause overall
overall_data <- grouped_data %>%
  group_by(death_cause) %>%
  summarise(totalcount = sum(count)) %>%
  ungroup %>%
  as.data.frame()

overall_data <- overall_data[order(-overall_data$totalcount), ]
top_ten_causes <- overall_data[2:10, "death_cause"]
top_ten_causes <- gsub("*, ICD10", "", top_ten_causes)

grouped_data$death_cause2 <- grouped_data$death_cause
grouped_data1 <- grouped_data %>%
  filter (death_cause %in% top_ten_causes)
grouped_data2 <- grouped_data %>%
  filter (!death_cause %in% c(top_ten_causes, "All causes"))
grouped_data2$death_cause2 <- "Others"

grouped_data <- rbind(grouped_data1[, c(1,3,4)], grouped_data2[, c(1,3,4)])
names(grouped_data) <- c("country", "count", "death_cause")

pivotted_data <- pivot_by_country(grouped_data)

# Getting the coordinates of each country
country_lookup <- read.csv(paste0("./Data/", "countries.csv"), stringsAsFactors = F)
names(country_lookup)[1] <- "country_code"

# Combining data
final_data <- merge(x = pivotted_data, y = country_lookup, by.x = "country", by.y = "name", all.x = T)

# Data cleaning for plotting
final_data <- unique(final_data)
multiplier <- log10(final_data$Total) / log10(max(final_data$Total))
final_data <- cbind(final_data, multiplier)

# Using map_data()
worldmap <- map_data ("world")

mapplot1 <- ggplot(worldmap) + 
  geom_map(data = worldmap, map = worldmap, aes(x=long, y=lat, map_id=region), col = "white", fill = "gray50") +
  geom_scatterpie(aes(x=longitude, y=latitude, group = country, r = multiplier*6), 
                  data = final_data, cols = colnames(final_data[,c(2:11)])) +
  xlim(-20,60) + ylim(10, 75) +
  scale_fill_brewer(palette = "Paired") +
  geom_text(aes(x=longitude, y=latitude, group = country, label = country), data = final_data, stat = "identity",
            position = position_dodge(width = 0.75), hjust = 1.5, #vjust = -1.5, size = 5, angle = 45,
            check_overlap = TRUE, na.rm = FALSE, show.legend = NA, 
            inherit.aes = TRUE) +
  labs(title = "Causes of death by country", x = "Longitude", y = "Latitude") +
  theme(legend.position = "top")

mapplot1

# Using borders()
mapWorld <- borders("world", colour="gray50", fill="gray50") # create a layer of borders

# Create the plot
mapplot2 <- ggplot(data = final_data, aes(x=longitude, y=latitude), group = country) +
  borders("world", colour="gray50", fill="gray50") +
  geom_scatterpie(aes(x=longitude, y=latitude, group = country, r = multiplier*6), 
                  data = final_data, cols = colnames(final_data[,c(2:11)])) +
  xlim(-20,60) + ylim(10, 75) +
  scale_fill_brewer(palette = "Paired") +
  geom_text(aes(x=longitude, y=latitude, group = country, label = country), data = final_data, stat = "identity",
            position = position_dodge(width = 0.75), hjust = 1.5, #vjust = -1.5, size = 5, angle = 45,
            check_overlap = TRUE, na.rm = FALSE, show.legend = NA, 
            inherit.aes = TRUE) +
  labs(title = "Causes of death by country", x = "Longitude", y = "Latitude") +
  theme(legend.position = "top")

mapplot2

# Using shapefile / geom_polygon
SHAPE_FILE_PATH = "./Data/World_Countries/World_Countries.shp"
world <- readOGR(dsn = SHAPE_FILE_PATH)

world <- fortify(world)

mapplot3 <- ggplot(data = world, aes(long, lat, group=group)) +
  geom_polygon(color = "white", fill  = "gray50") +
  geom_scatterpie(aes(x=longitude, y=latitude, group = country, r = multiplier*6), 
                  data = final_data, cols = colnames(final_data[,c(2:11)])) +
  xlim(-20,60) + ylim(10, 75) +
  scale_fill_brewer(palette = "Paired") +
  geom_text(aes(x=longitude, y=latitude, group = country, label = country), data = final_data, stat = "identity",
            position = position_dodge(width = 0.75), hjust = 1.5, #vjust = -1.5, size = 5, angle = 45,
            check_overlap = TRUE, na.rm = FALSE, show.legend = NA, 
            inherit.aes = TRUE) +
  labs(title = "Causes of death by country", x = "Longitude", y = "Latitude") +
  theme(legend.position = "top")

mapplot3


# Save plot
ggsave(filename = "./Output/1. Map plot - Leading causes of death by country.png", mapplot1,
       width = 13,
       height = 8.5,
       units = "in",
       device = "png"
)
