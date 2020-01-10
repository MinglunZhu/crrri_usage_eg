Sys.setenv(DEBUGME = 'crrri')

library(debugme)
library(promises)
library(crrri)
#library(decapitated)
library(rvest)
library(dplyr)

#consts
CUR <- 'cny'
#CUR <- 'thb'

L_URL <- 'example url for login page'
SC_URL <- 'example url for captcha code'

AFF_INFO_URL <- 'example scrape url 1?aCode='
AFF_SCHEME_URL <- 'example scrape url 2?acode='

INFO_IDS <- c('lblUsername', "lblRemarks", "lblWebsite", "lblIsActive")
SCHEME_IDS <- c("txtLostTo1", "txtLostTo2", "txtLostFrom3", "txtNoFrom1", "txtNoFrom2", "txtNoFrom3", "txtRate1", "txtRate2", "txtRate3", "txtFDeposit1", "txtFDeposit2", "txtFDeposit3", "txtBoosterRate1", "txtBoosterRate2", "txtBoosterRate3")

DF_COLS <- c('un', 'rmk', 'ws', 'isActive', 'ngr_1', 'ngr_2', 'ngr_3', 'wgrMbrCnt_1', 'wgrMbrCnt_2', 'wgrMbrCnt_3', 'rate_1', 'rate_2', 'rate_3', 'first_dpsCnt_1', 'first_dpsCnt_2', 'first_dpsCnt_3', 'bonRate_1', 'bonRate_2', 'bonRate_3')

AFF_HP_URL <- 'example scrape site homepage url'
#end consts

#set environment variable
Sys.setenv(HEADLESS_CHROME = 'C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe')

chrome <- Chrome$new()

client <- chrome$connect(callback = function(client) {
  nw <- client$Network
  pg <- client$Page
  
  nw$enable() %...>% { 
    pg$enable()
  } %...>% {
    nw$setCacheDisabled(cacheDisabled = TRUE)
  } %...>% {
    pg$navigate(url = L_URL)
  }
  
  client$inspect()
})

##############################################################################################################################################SEPERATOR

#navigate to aff pg
#dump dom
#parse and get dom info with rvest
pg <- client$Page
rt <- client$Runtime

readVal <- function(url, affCode, ids, isValue = FALSE) {
  pg$navigate(url = paste0(url, affCode)) %...>% {
    pg$loadEventFired() 
  } %...>% {
    rt$evaluate(
      expression = 'document.documentElement.outerHTML'
    )
  } %...>% (function(result) {
    html <- paste(result$result$value, sep = '\n')
    
    #read in rvest
    dom <- xml2::read_html(html)
    
    #read values into vector
    if (isValue) {
      sapply(ids, function(id) {
        dom %>%
          html_node(paste0('#', id)) %>%
          html_attr('value')
      })
    } else {
      sapply(ids, function(id) {
        dom %>%
          html_node(paste0('#', id)) %>%
          html_text()
      })
    }
  })
}

readAffTree <- function(affCode) {
  pg$navigate(url = AFF_HP_URL) %...>% {
    pg$loadEventFired()
  } %...>% {
    rt$evaluate(
      expression = paste0("
        const MENU_FRAME = document.getElementById('frleft'),
              MAIN_FRAME = document.getElementById('i9999'),
              MAIN_WDW = MAIN_FRAME.contentWindow,
              LNK = MENU_FRAME.contentWindow.document.querySelector('#trMenu1 a[title=\"Affiliate Tree\"]');
        
        const EVT = document.createEvent('MouseEvents');
        
        EVT.initEvent('click', true, true);
        EVT.synthetic = true;
        
        const P = new Promise(function(ff) {
          MAIN_FRAME.addEventListener('load', function(evt) {
            ff();
          }, {
            once: true
          });
        });
        
        LNK.dispatchEvent(EVT, true);
        
        let ffed = false;
        
        P.then(function() {
          const MAIN_DOC = MAIN_WDW.document,
                IPT = MAIN_DOC.querySelector('#Label7 + input'),
                SEARCH_BTN = MAIN_DOC.getElementById('btnSearch');
        
          IPT.value = '", affCode, "';
        
          const EVT = MAIN_DOC.createEvent('MouseEvents');
        
          EVT.initEvent('click', true, true);
          EVT.synthetic = true;
          
          const P = new Promise(function(ff) {
            MAIN_FRAME.addEventListener('load', function(evt) {
              ff();
            }, {
              once: true
            });
          });
        
          SEARCH_BTN.dispatchEvent(EVT, true);
        
          return P;
        }).then(function() {
          ffed = true;
        });
      ")
    )
  } %...>% (function(r) {
    promise(function(ff, rjc) {
      chkFfed <- function() {
        rt$evaluate(
          expression = 'ffed'
        ) %...>% (function(ffed) {
          if (ffed$result$value) {
            ff(TRUE)
          } else {
            later::later(
              chkFfed,
              delay = 1
            )
          }
        })
      }
      
      chkFfed()
    })
  }) %...>% {
    rt$evaluate(
      expression = 'MAIN_WDW.document.documentElement.outerHTML'
    )
  } %...>% (function(result) {
    html <- paste(result$result$value, sep = '\n')
    
    #read in rvest
    dom <- xml2::read_html(html)
    
    rate <- dom %>%
      html_node('#divRemark + table .redpercent') %>%
      html_text()
    
    rate <- gsub('[^0-9.]', '', rate)
    
    c(0, 0, 0, 0, 0, 0, rate, rate, rate, 0, 0, 0, 0, 0, 0)
  })
}

#for scraping chinese characters
if (CUR == 'cny') {
  Sys.setlocale(locale="Chinese")
} else {
  Sys.setlocale(locale="Thai")
}


affScheme_df <- data.frame()
cmAffs_df <- data.frame()

appendAffRowP <- function(affCode) {
  #read info
  info_vec <- c()
  tmp_aff_df <- data.frame()
  
  readVal(AFF_INFO_URL, affCode, INFO_IDS) %...>% (function(val) {
    #store info
    info_vec <<- val#save to global scope because within promise there's no way to return the val
  }) %...>% {
    #read scheme
    readVal(AFF_SCHEME_URL, affCode, SCHEME_IDS, TRUE)
  } %...>% (function(val) {
    #if scheme is na, chk aff tree
    if (is.na(val[5])) {
      readAffTree(affCode)
    } else {
      val
    }
  }) %...>% (function(val) {  
    #store scheme
    cmbVal <- c(info_vec, val)
    
    #convert to data frame
    tmp_aff_df <<- data.frame(t(cmbVal))
    
    colnames(tmp_aff_df) <<- DF_COLS
    
    #combine vec
    if (nrow(affScheme_df) == 0) {
      affScheme_df <<- tmp_aff_df
    } else {
      affScheme_df <<- rbind(affScheme_df, tmp_aff_df)
    }
  })
}

chain2AffPs <- function(ipt1, ipt2) {
  p <- ipt1
  
  if (is.character(ipt1)) {
    p <- appendAffRowP(ipt1)
  }
  
  p %...>% {
    appendAffRowP(ipt2)
  }
}

chainAffPs <- function(affCodes) {
  Reduce(chain2AffPs, affCodes)
}

#get affiliate codes
affLst_df <- read.csv('revShare/ipt/affLst.csv', colClasses = c('character'))

#if only 1 affCode, then the reduce will not run, so we have to call single and not chain
if (nrow(affLst_df) > 1) {
  p <- chainAffPs(affLst_df$affCode)
} else {
  p <- appendAffRowP(affLst_df$affCode[1])
}

p %...>% {
  chrome$close()
  
  affScheme_df <- affScheme_df %>%
    mutate(
      rmk = enc2utf8(as.character(rmk)),
      ngr_1 = as.numeric(as.character(ngr_1)),
      ngr_2 = as.numeric(as.character(ngr_2)),
      ngr_3 = as.numeric(as.character(ngr_3)),
      wgrMbrCnt_1 = as.numeric(as.character(wgrMbrCnt_1)),
      wgrMbrCnt_2 = as.numeric(as.character(wgrMbrCnt_2)),
      wgrMbrCnt_3 = as.numeric(as.character(wgrMbrCnt_3)),
      rate_1 = as.numeric(as.character(rate_1)) / 100,
      rate_2 = as.numeric(as.character(rate_2)) / 100,
      rate_3 = as.numeric(as.character(rate_3)) / 100,
      first_dpsCnt_1 = as.numeric(as.character(first_dpsCnt_1)),
      first_dpsCnt_2 = as.numeric(as.character(first_dpsCnt_2)),
      first_dpsCnt_3 = as.numeric(as.character(first_dpsCnt_3)),
      bonRate_1 = as.numeric(as.character(bonRate_1)) / 100,
      bonRate_2 = as.numeric(as.character(bonRate_2)) / 100,
      bonRate_3 = as.numeric(as.character(bonRate_3)) / 100
    )
  
  if (CUR == 'thb') {
    affScheme_df <- affScheme_df %>%
      mutate(
        ngr_2 = ngr_1,
        ngr_3 = ngr_1,
        wgrMbrCnt_3 = wgrMbrCnt_2,
        rate_3 = rate_2,
        first_dpsCnt_3 = first_dpsCnt_2,
        bonRate_3 = bonRate_2
      )
  }
  
  #add affCode
  affScheme_df <- cbind(affLst_df, affScheme_df)
  
  #ud rcds
  #had to use readr because normal read.csv has trouble with UTF-8
  rcds_affInfo <- readr::read_csv(paste0('rcds/affInfo_', CUR, '.csv'))
  
  #clean old rcds of the affiliates
  rcds_affInfo <- rcds_affInfo %>%
    filter(!(affCode %in% affScheme_df$affCode))
  
  #append updated info
  rcds_affInfo <- rbind(rcds_affInfo, affScheme_df)
  
  #write rcds
  write.csv(
    rcds_affInfo,
    paste0('rcds/affInfo_', CUR, '.csv'),
    fileEncoding = 'UTF-8',
    row.names = FALSE
  )
  
  #reset locale when done so as to not mess with other scripts
  Sys.setlocale(locale="English")
}
