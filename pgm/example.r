library("stats")
library("VGAM")
#library("msm")
#library("flexsurv")
#library("Hmisc")


### STUDY SPECIFIC, POINT TO THE WORKING DIRECTORY
setwd('C:/Users/M150963/Dropbox/myResearch/eventForcasting/rprog/')

source('utilsBayes1.r')
source('utilsFreq.r')
source('utilsWts.r')

rgompertz<-flexsurv::rgompertz
dgompertz<-flexsurv::dgompertz
pgompertz<-flexsurv::pgompertz
qgompertz<-flexsurv::qgompertz


N <-1000 # number to simulate for the full data set.

### STUDY SPECIFIC, THE NUMBER OF EVENTS YOU ARE TRYING TO PREDICT
nE<-775 # landmark event number

### STUDY SPECIFIC, THE CSV FILE SHOULD CONTAIN 3 COLUMN, ONSTUDY, EVENT_TIME, AND EVENT INDICATOR
### THE ONSTUDY AND EVENT TIME WILL NEED TO BE CONVERTED SO FIRST PATINET ON STUDY IS DAY 0 (NOT CALENDAR DATE )
tempdat <- read.csv("sample.csv")

dat <- cbind(tempdat[,1], tempdat[,2]*tempdat[,3])
# FIRST COLUMN IS ONSTUDY
# SECOND COLUMN IS EVENT TIME (IF EVENT OCCURED) AND ZERO IF NO EVENT


### STUDY SPECIFIC, ASSUME EXPONENTIAL DISTRIBUTION THE RATE PARAMETER (LAMBDA) THE UNIT IS IN DAYS
### THIS IS FROM THE HISTORICAL DATA WHICH USED FOR THE CONTROL ARM
lambda <- 0.0003255076

#Priors
# Weibull prior, mean and varaince for lambda and k
wP<-c(lambda, 50, 1, 50)  

# Gompertz prior, mean and variance for eta and b
b <- lambda*log(log(2)+1)/log(2)
gP<-c(1, 50, b, 50)

# Lon-logistic prior, mean and variance for alpha and beta
llP<-c(1/lambda, 50, 1, 50)

# Log-normal prior, mean and varaince for mu and sigma
mu <- -1*log(lambda)-log(2)/2
lnP<-c(mu, 50, sqrt(log(2)), 50)

cTime<-max(dat)

#Frequentist Predictions
freqRes<-getFreqInts(dat,nE,MM=200)
# freqRes[[1]] are the 7 predictions in the same order 
#     as the paper tables
# freqRes[[2]] are the prediction intervals in the paper
# freqRes[[3]] is a symmetric prediction interval not included
#     in the paper

#Bayes predictions
BayesRes<-getBayesInt(dat,nE,wP,lnP,gP,llP,MM=800)    
# BayesRes[[1]] are the 7 predictions in the same order 
#     as the paper tables
# BayesRes[[2]] are the prediction intervals in the paper
# BayesRes[[3]] is a symmetric prediction interval not included
#     in the paper



# PLOT OUTPUTS
mean <- c(freqRes[[1]], BayesRes[[1]])
lower <- c(freqRes[[2]][,1], BayesRes[[2]][,1])
upper <- c(freqRes[[2]][,2], BayesRes[[2]][,2])
methodText <- cbind(c("Freq-Weibull", "Freq-LogNormal", "Freq-Gompertz", "Freq-LogLogistic", 
                "Freq-PredSyn(Avg)", "Freq-PredSyn(MSPE)", "Freq-PredSyn(Vote)", 
                "Bayes-Weibull", "Bayes-LogNormal", "Bayes-Gompertz", "Bayes-LogLogistic", 
                "Bayes-PredSyn(Avg)", "Bayes-PredSyn(MSPE)", "Bayes-PredSyn(Vote)"), rep(" ", 14))

library(rmeta)
xmin<-floor(min(lower)/50)*50
xmax<-ceil(max(upper)/50)*50

forestplot(methodText, mean, lower, upper, clip = c(xmin, xmax), zero=xmin,
           xlab=c("Days since first pt on-study"), xticks=seq(xmin, xmax, by=100), boxsize=0.3)


