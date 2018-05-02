###########################################
### Setup
###########################################
library(tidyverse)
library(markdown)
library(shiny)
library(shinythemes)
library(DT)
library(flexsurv)
library(quadprog)
library(Hmisc)
library(msm) 
library(VGAM)
library(rmeta)
library(ggplot2)
library(scales)
library(ggstance, lib.loc = here::here("rpkgs"))
library(plotly)
library(knitr)
library(kableExtra)
theme_set(theme_classic())
source(here::here("pgm","utilsBayes1.r"))
source(here::here("pgm","utilsFreq.r"))
source(here::here("pgm","utilsWts.r"))
source(here::here("pgm", "helper.R"))
###########################################
### User Interface
###########################################

ui <- fluidPage(
  theme = "mayo_theme.css",
  withMathJax(),
  useShinyjs(),
  navbarPage(
    title = "Milestone prediction",
    tabPanel("Main",
             sidebarPanel(
               textInput("study_title", label = "Study Name", value = "Enter Study Name", width = 300),
               numericInput("nE", label = "Mileston (number of events)", value = 1000, width = 300),
               dateInput("study_date",label = "First patient enrollment date", value = "2018-01-01", width = 300,format = "yyyy-mm-dd"),
               tags$h6("Date format: yyyy-mm-dd"),
               HTML("<br/>"),
               fileInput("inputfile", NULL, buttonLabel = "Upload", multiple = FALSE, width = 300),
               tags$h6("*File upload format can be found in the 'About' tab"),
               radioButtons(inputId="calculation", label="If you wish to use defult priors for baysian estimates please check on of the follow options to provide historic event rate; otherwise see the 'Custom Prior Distributions' tab.", 
                            choices=c("Cumulative Survial Percentage",
                                      "Median Survival Time",
                                      "Hazard Rate"), selected = "Hazard Rate"),
               conditionalPanel(
                   condition = "input.calculation == 'Cumulative Survial Percentage'",
                   numericInput("survProp", label = "Survival Percentage (0-100)", value = 0, min = 0, 100),
                   numericInput("cutoff", label = "Number of Days", value = 0, width = 300)
                 ),
                 conditionalPanel(
                   condition = "input.calculation == 'Median Survival Time'",
                   numericInput("medianTime", label = "Days", value = 0, width = 300)
                 ),
                 conditionalPanel(
                   condition = "input.calculation == 'Hazard Rate'",
                   numericInput("lambda", label = "Lambda", value = 0.0003255076, width = 300)
                 ),
               numericInput("seed", label = "Set Random Seed", value = 7 , width = 300)
               
             ),
             mainPanel(
               tabsetPanel(
                 tabPanel("Data View",
                          dataTableOutput("data_view"),
                          tags$h3(textOutput("data_checks"))
                 ),
                 tabPanel("Customize Prior Distributions",
                          div(
                          id = "reset",
                          tags$h3("Weibullprior"),
                          div(style="display:inline-block",numericInput(inputId="meanlambda", label="Mean of Lambda", value = 0.0003255076, width = 95)),
                          div(style="display:inline-block",numericInput(inputId="varlambda", label="Variance of Lambda", value = 10, width = 95)),
                          div(style="display:inline-block",numericInput(inputId="meank", label="Mean of k", value = 1, width = 95)),
                          div(style="display:inline-block",numericInput(inputId="vark", label="Variance of k", value = 10, width = 95)),
                          tags$h3("Gompertz"),
                          div(style="display:inline-block",numericInput(inputId="meaneta", label="Mean of ETA", value = 1, width = 95)),
                          div(style="display:inline-block",numericInput(inputId="vareta", label="Variance of ETA", value = 10, width = 95)),
                          div(style="display:inline-block",numericInput(inputId="meanb", label="Mean of b", value = 0.0002472905, width = 95)),
                          div(style="display:inline-block",numericInput(inputId="varb", label="Variance of b", value = 10, width = 95)),
                          tags$h3("Log-logistic prior"),
                          div(style="display:inline-block",numericInput(inputId="meanalpha", label="Mean of Alpha", value = 3072.125, width = 95)),
                          div(style="display:inline-block",numericInput(inputId="varalpha", label="Variance of Alpha", value = 30721.25, width = 95)),
                          div(style="display:inline-block",numericInput(inputId="meanbeta", label="Mean of Beta", value = 1, width = 95)),
                          div(style="display:inline-block",numericInput(inputId="varbeta", label="Variance of Beta", value = 10, width = 95)),
                          tags$h3("Log-normal"),
                          div(style="display:inline-block",numericInput(inputId="meanmu", label="Mean of Mu", value = 7.683551, width = 95)),
                          div(style="display:inline-block",numericInput(inputId="varmu", label="Variance of Mu", value =  76.83551, width = 95)),
                          div(style="display:inline-block",numericInput(inputId="meansigma", label="Mean of Sigma", value = 0.8325546, width = 95)),
                          div(style="display:inline-block",numericInput(inputId="varsigma", label="Variance of Sigma", value = 10, width = 95))),
                          tags$hr(),
                          actionButton("reset_input", "Reset All Priors to Default")
                          ),
                 
                 tabPanel("Calculate Milestone",
                          actionButton("calculate", label = "Run Milestone Prediction"),
                          plotOutput("forestPlot", width = "100%"),
                          tableOutput("table1"),
                          tableOutput("table2"),
                          downloadButton("report", "Generate report")
                 )
               )
             )
    ),
    tabPanel("About",
             includeMarkdown(here::here("markdown", "About.md"))
    ),
    tabPanel("Bayesian Prior Tab",
             includeMarkdown(here::here("markdown", "Bayesian.md")))
  )
)

##########################################
### Server
##########################################

server <- function(input, output, session) {
  
  lambda <- reactive({
    if (input$calculation == 'Cumulative Survial Percentage'){
      -log(input$survProb)/input$cutoff
    } else if (input$calculation == 'Median Survival Time'){
      -log(0.5)/input$medianTime
    } else input$lambda
  })
  
  inputData <- eventReactive(input$inputfile, {
    read <- input$inputfile
    if (is.null(read)){
      return()
    }
    read_any_file(read$datapath)
  })
  
  data_check_text <- eventReactive(input$inputfile,{
    if (is.numeric(inputData()[[1]]) & !anyNA(inputData()[[1]])) {
      check1 <- "Column 1 is OK"
      }
    else {
      "Bad"
    }
  })
  
  predictions <- eventReactive(input$calculate,{
    withProgress(value = 0, message =  "Calculating", {
      nE <- input$nE # landmark event number
      tempdat <- inputData()
      dat <- cbind(tempdat[[1]], tempdat[[2]] * tempdat[[3]])
      #lambda <- 0.0003255076
      
      #Priors
      # Weibull prior, mean and varaince for lambda and k
      wP <- c(lambda(), input$varlambda, input$meank, input$vark)
      
      # Gompertz prior, mean and variance for eta and b
      b <- lambda() * log(log(2) + 1) / log(2)
      gP <- c(input$meaneta, input$vareta, input$meanb, input$varb)
      
      # Lon-logistic prior, mean and variance for alpha and beta
      llP <- c(input$meanalpha, input$varalpha, input$meanbeta, input$varbeta)
      
      # Log-normal prior, mean and varaince for mu and sigma
      mu <- -1 * log(lambda()) - log(2) / 2
      lnP <- c(input$meanmu, input$varmu, input$meansigma, input$varsigma)
      
      cTime <- max(dat)
      
      incProgress(amount= .1, message = "Initialized values")
      
      #Frequentist Predictions
      set.seed(input$seed)
      freqRes <- getFreqInts(dat, nE, MM=200)
      
      incProgress(amount= .65, message = "Frequentist Predictions")
      
      #Bayes predictions
      set.seed(input$seed)
      BayesRes <- getBayesInt(dat, nE, wP, lnP, gP, llP, MM = 800)
      mean <- c(freqRes[[1]], BayesRes[[1]])
      lower <- c(freqRes[[2]][,1], BayesRes[[2]][,1])
      upper <- c(freqRes[[2]][,2], BayesRes[[2]][,2])
      methodText <- c("Freq-Weibull", "Freq-LogNormal", "Freq-Gompertz", "Freq-LogLogistic",
                            "Freq-PredSyn(Avg)", "Freq-PredSyn(MSPE)", "Freq-PredSyn(Vote)",
                            "Bayes-Weibull", "Bayes-LogNormal", "Bayes-Gompertz", "Bayes-LogLogistic",
                            "Bayes-PredSyn(Avg)", "Bayes-PredSyn(MSPE)", "Bayes-PredSyn(Vote)")
      
      xmin <- floor(min(lower) / 50) * 50
      xmax <- ceil(max(upper) / 50) * 50
      
      incProgress(amount = .95, message = "Bayes Predictions")
      
      plotdata <- data.frame(method = methodText,
                              mean = as.Date(mean, origin = input$study_date) ,
                              lower = as.Date(lower, origin = input$study_date),
                              upper = as.Date(upper, origin = input$study_date)) %>% 
        mutate(type = case_when(
          str_detect(method, pattern = "Freq") ~ "Frequentist",
          str_detect(method, pattern = "Bayes") ~ "Bayesian"),
          label = c("Weibull", "Log-Normal", "Gompertz", "Log-Logistic","Predictive Synthesis (Average)",
                    "Predictive Synthesis (MSPE)", "Predictive Synthesis (Vote)","Weibull", "Log-Normal", 
                    "Gompertz", "Log-Logistic","Predictive Synthesis (Average)",
                    "Predictive Synthesis (MSPE)", "Predictive Synthesis (Vote)"))
      plotdata
      
    })
  })
  
  
  output$report <- downloadHandler(
    filename = "report.html",
    content = function(file) {
      # Copy the report file to a temporary directory before processing it, in
      # case we don't have write permissions to the current working dir (which
      # can happen when deployed).
      tempReport <- file.path(tempdir(), "report.Rmd")
      file.copy("report.Rmd", tempReport, overwrite = TRUE)
      
      # Set up parameters to pass to Rmd document
      params <- list(data = predictions(), 
                     study = input$study_title,
                     first_date = input$study_date,
                     number_events = sum(inputData()[[3]]),
                     milestone = input$nE)
      
      # Knit the document, passing in the `params` list, and eval it in a
      # child of the global environment (this isolates the code in the document
      # from the code in this app).
      rmarkdown::render(tempReport, output_file = file,
                        params = params,
                        envir = new.env(parent = globalenv())
      )
    }
  )
  
  output$data_checks <- renderText({
    data_check_text()
  })
  
  output$data_view <- renderDataTable({
    inputData()
  }, rownames= FALSE)
  
  output$forestPlot <- renderPlot({
    p <- ggplot(predictions(), aes(x = mean, y = label, xmin = lower, xmax = upper)) +
      geom_pointrangeh() +
      facet_grid(type ~ ., scale = "free", switch="both") + 
      scale_x_date(labels = date_format("%Y-%m-%d")) +
      labs(y = "Days since first patient enrolled", x = "")
    p
  })
  
  output$table1 <- function(){
    all <- predictions() %>%
      mutate(label2 = case_when(
        method == "Bayes-Gompertz" ~ "Gompertz",
        method == "Bayes-LogLogistic" ~ "Log-Logistic",
        method == "Bayes-LogNormal" ~ "Log-Normal",
        method == "Bayes-PredSyn(Avg)" ~ "Predicitive Synthesis (Average)",
        method == "Bayes-PredSyn(MSPE)" ~ "Predicitive Synthesis (MSPE)",
        method == "Bayes-PredSyn(Vote)" ~ "Predicitive Synthesis (Vote)",
        method == "Bayes-Weibull" ~ "Weibull",
        method == "Freq-Gompertz" ~ "Gompertz",
        method == "Freq-LogLogistic" ~ "Log-Logistic",
        method == "Freq-LogNormal" ~ "Log-Normal",
        method == "Freq-PredSyn(Avg)" ~ "Predicitive Synthesis (Average)",
        method == "Freq-PredSyn(MSPE)" ~ "Predicitive Synthesis (MSPE)",
        method == "Freq-PredSyn(Vote)" ~ "Predicitive Synthesis (Vote)",
        method == "Freq-Weibull" ~ "Weibull")) %>%
      select(label2, lower, mean, upper) %>%
      setNames(c("Method", "Lower bound", "Prediction", "Upper bound"))
    
    freq <- filter(all, row_number() <=7)
    kable(freq, "html") %>%
      kable_styling(bootstrap_options = c("striped", "hover"))
  }
  
  output$table2 <- function(){
    all <- predictions() %>%
      mutate(label2 = case_when(
        method == "Bayes-Gompertz" ~ "Gompertz",
        method == "Bayes-LogLogistic" ~ "Log-Logistic",
        method == "Bayes-LogNormal" ~ "Log-Normal",
        method == "Bayes-PredSyn(Avg)" ~ "Predicitive Synthesis (Average)",
        method == "Bayes-PredSyn(MSPE)" ~ "Predicitive Synthesis (MSPE)",
        method == "Bayes-PredSyn(Vote)" ~ "Predicitive Synthesis (Vote)",
        method == "Bayes-Weibull" ~ "Weibull",
        method == "Freq-Gompertz" ~ "Gompertz",
        method == "Freq-LogLogistic" ~ "Log-Logistic",
        method == "Freq-LogNormal" ~ "Log-Normal",
        method == "Freq-PredSyn(Avg)" ~ "Predicitive Synthesis (Average)",
        method == "Freq-PredSyn(MSPE)" ~ "Predicitive Synthesis (MSPE)",
        method == "Freq-PredSyn(Vote)" ~ "Predicitive Synthesis (Vote)",
        method == "Freq-Weibull" ~ "Weibull")) %>%
      select(label2, lower, mean, upper) %>%
      setNames(c("Method", "Lower bound", "Prediction", "Upper bound"))
    
    bayes <- filter(all, row_number() > 7)
    
    kable(bayes, "html") %>%
      kable_styling(bootstrap_options = c("striped", "hover"))
  }
  
  ##### Reset button ########
  observeEvent(input$reset_input, {
    #reset("reset")
    ## Weibull
    updateml <- lambda()
    updatevl <- 10*max(lambda(),1)
    updateNumericInput(session, "meanlambda", value = updateml)
    updateNumericInput(session, "varlambda", value = updatevl)
    updateNumericInput(session, "meank", value = 1)
    updateNumericInput(session, "vark", value = 10)
    
    ## Gompertz
    updatemb <- lambda()*log(log(2)+1)/log(2)
    updatevb <- 10*max(updatemb,1)
    updateNumericInput(session, "meaneta", value = 1)
    updateNumericInput(session, "vareta", value = 10)
    updateNumericInput(session, "meanb", value = updatemb)
    updateNumericInput(session, "varb", value = updatevb)
    
    ## Log-logistic
    updatema <- 1/lambda()
    updateva <- 10*max(updatema,1)
    updateNumericInput(session, "meanalpha", value = updatema)
    updateNumericInput(session, "varalpha", value = updateva)
    updateNumericInput(session, "meanbeta", value = 1)
    updateNumericInput(session, "varbeta", value = 10)
    
    ## Log-logistic
    updatemu <- -1*log(lambda())-log(2)/2
    updatevmu <- 10*max(updatemu,1)
    updatems <- sqrt(log(2))
    updatevs <- 10
    updateNumericInput(session, "meanmu", value = updatemu)
    updateNumericInput(session, "varmu", value = updatevmu)
    updateNumericInput(session, "meansigma", value = updatems)
    updateNumericInput(session, "varsigma", value = updatevs)
  })
  
  
  
}

##########################################
### Knit app together 
##########################################
shinyApp(ui, server)