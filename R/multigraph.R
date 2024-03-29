# create json for multigraph
multigraphJSON <- function(multi,dir){
json <- character(0)
types <- character(0)
items <- character(0)
for(item in names(multi)){
  graph <- multi[[item]]
  gClass <- ""
  jsongraph <- "{}"
  if(inherits(graph,"network_rd3")){
    gClass <- "network"
    jsongraph <- imgWrapper(graph,networkJSON,dir)
  }else if(inherits(graph,"timeline_rd3")){
    gClass <- "timeline"
    jsongraph <- timelineJSON(graph)
  }else if(inherits(graph,"barplot_rd3")){
    gClass <- "barplot"
    jsongraph <- barplotJSON(graph)
  }else if(inherits(graph,"gallery_rd3")){
    gClass <- "gallery"
    jsongraph <- imgWrapper(graph,galleryJSON,dir)
  }else if(inherits(graph,"pie_rd3")){
    gClass <- "pie"
    jsongraph <- pieJSON(graph)
  }else if(is.character(graph) && file.exists(paste0(graph,'/index.html'))){
    gClass <- "iFrame"
    graphName <- sub("^.*/","",graph)
    dir.create(paste0(dir,'/data'), showWarnings = FALSE)
    file.copy(graph, paste0(dir,'/data'), recursive = TRUE)
    jsongraph <- toJSON(paste0('data/',graphName))
  }else if(inherits(graph,"evolMap")){
    gClass <- "iFrame"
    dir.create(paste0(dir,'/data'), showWarnings = FALSE)
    objCreate(graph,paste0(dir,'/data/',item))
    jsongraph <- toJSON(paste0('data/',item))
  }else{
    warning(paste0('Not supported object "',item,'".'))
    next
  }
  json <- c(json,jsongraph)
  types <- c(types,toJSON(gClass))
  items <- c(items,toJSON(item))
}
json <- paste0(json,collapse=',')
types <- paste0(types,collapse=',')
items <- paste0(items,collapse=',')
return(paste0('{"items":[',items,'],"types":[',types,'],"data":[',json,']}'))
}

multiGraph <- function(multi,dir){
  language <- unique(unlist(lapply(multi,getLanguageScript)))
  if(length(language)!=1)
    language <- "en.js"
  styles <- c("reset.css","styles.css")
  scripts <- c("d3.min.js","jspdf.min.js","jszip.min.js","iro.min.js","images.js","colorScales.js","functions.js",language,"multigraph.js")
  for(i in seq_along(multi)){
    graph <- multi[[i]]
    if(inherits(graph,"network_rd3")){
      scripts <- c(scripts,"network.js")
    }
    if(inherits(graph,"timeline_rd3")){
      scripts <- c(scripts,"timeline.js")
    }
    if(inherits(graph,"barplot_rd3")){
      scripts <- c(scripts,"barplot.js")
    }
    if(inherits(graph,"gallery_rd3")){
      scripts <- c(scripts,"gallery.js")
      if(!is.null(graph$options$tutorial) && !identical(as.logical(graph$options$tutorial),FALSE)){
        scripts <- c(scripts,"tutorial.js",paste0("tutorial_",language))
        styles <- c(styles,"tutorial.css")
      }
    }
    if(inherits(graph,"pie_rd3")){
      scripts <- c(scripts,"pie.js")
    }
  }
  styles <- unique(styles)
  scripts <- unique(scripts)
  createHTML(dir, styles, scripts, function(){ return(multigraphJSON(multi,dir)) })
}

polyGraph <- function(multi,mfrow,dir){
  createHTML(dir, NULL, "polygraph.js", toJSON(list(options=list(mfrow=mfrow,n=length(multi)))))
  if(mfrow[1]*mfrow[2]>2){
    for(i in seq_along(multi)){
      multi[[i]]$options$controls <- NULL
    }
  }
  multiGraph(multi,paste0(dir,"/multiGraph"))
}

evolvingWrapper <- function(multi,frame,speed,loop=FALSE,lineplots=NULL){
  if(length(multi)<2){
    stop("Cannot make an evolving network with only one graph")
  }

  if(!all(vapply(multi, inherits, TRUE, what = "network_rd3"))){
    stop("All graphs must be 'network_rd3' objects")
  }

  if(is.null(names(multi)) || !all(!duplicated(names(multi)))){
    message("Graph names will be generated automatically")
    names(multi) <- paste0("graph",seq_along(multi))
  }

  if(!(is.numeric(frame) && frame>=0)){
      frame <- formals(evolNetwork_rd3)[["frame"]]
      warning("frame: must be integer greater than 0")
  }
  if(!(is.numeric(speed) && speed>=0 && speed<=100)){
      speed <- formals(evolNetwork_rd3)[["speed"]]
      warning("speed: must be numeric between 0 and 100")
  }

  name <- unique(vapply(multi,function(x){ return(x$options$nodeName) },character(1)))
  if(length(name)!=1)
    stop("name: all graphs must have the same name")
  nodenames <- colnames(multi[[1]]$nodes)
  linknames <- colnames(multi[[1]]$links)
  for(m in multi){
    if(!identical(nodenames,colnames(m$nodes)))
      stop("nodes: all graphs must have the same node columns")
    if(!identical(linknames,colnames(m$links)))
      stop("links: all graphs must have the same link columns")
  }

  frames <- names(multi)

  links <- lapply(multi,function(x){ return(x$links) })
  for(i in seq_along(frames)){
    if(!is.null(links[[i]])){
      links[[i]][["_frame_"]] <- i-1
    }
  }
  links <- do.call(rbind,links)
  rownames(links) <- NULL

  nodes <- data.frame(name=unique(unlist(lapply(multi,function(x){ return(x$nodes[[name]]) }))))
  nodes$name <- as.character(nodes$name)
  names(nodes) <- name
  for(n in nodenames){
    if(n!=name){
      nodes[[n]] <- sapply(nodes[[name]],function(x){
        values <- sapply(frames,function(f){
          return(multi[[f]]$nodes[x,n])
        })
        aux <- unique(values)
        if(length(aux)==1)
          return(aux)
        if(length(aux)<1)
          return(NA)
        values <- as.character(values)
        values[is.na(values)] <- ""
        return(paste0(values,collapse="|"))
      })
    }
  }

  options <- multi[[1]]$options
  getAll <- function(opt,item){
      items <- sapply(multi,function(x){
        if(!is.null(x$options[[item]]))
          return(x$options[[item]])
        else
          return(NA)
      })
      if(length(unique(items))!=1)
        opt[[item]] <- items
      return(opt)
  }
  for(i in c("main","note","repulsion","distance","zoom"))
    options <- getAll(options,i)
  options$frames <- frames
  options$frame <- frame
  options$speed <- speed
  if(identical(loop,TRUE)){
    options$loop <- TRUE
  }
  lineplots <- intersect(as.character(lineplots),union(union(names(nodes),names(links)),"degree"))
  if(length(lineplots)){
    options$lineplotsKeys <- lineplots
  }
  net <- structure(list(links=links,nodes=nodes,options=options),class="network_rd3")

  tree <- list()
  for(i in seq_along(frames)){
    if(!is.null(multi[[i]]$tree)){
      tree[[i]] <- multi[[i]]$tree
      tree[[i]][["_frame_"]] <- i-1
    }
  }
  if(length(tree)){
    tree <- do.call(rbind,tree)
    rownames(tree) <- NULL
    net$tree <- tree
  }

  return(net)
}

#create html wrapper for multigraph
rd3_multigraph <- function(..., mfrow = NULL, dir = NULL){
  graphs <- list(...)

  addGraph <- function(res,g,n){
    if(is.null(n)){
      n <- paste0("graph",length(res)+1)
    }
    res[[n]] <- g
    return(res)
  }

  res <- list()
  nam <- character()
  for(i in seq_along(graphs)){
    g <- graphs[[i]]
    check <- FALSE
    for(cls in c("network_rd3","timeline_rd3","barplot_rd3","gallery_rd3","pie_rd3","multi_rd3","evolMap")){
      if(inherits(g,cls)){
        check <- TRUE
        break
      }
    }
    if(is.character(g) && file.exists(paste0(g,'/index.html'))){
      check <- TRUE
    }
    if(check){
      if(inherits(g,"multi_rd3")){
        for(j in seq_along(g$graphs)){
          gg <- g$graphs[[j]]
          res <- addGraph(res,gg,names(g$graphs)[j])
        }
      }else{
        res <- addGraph(res,g,names(graphs)[i])
      }
    }else{
      warning('Not supported object found.')
    }
  }

  options <- list()
  if(!is.null(mfrow)){
    if(is.numeric(mfrow) && length(mfrow)==2){
      options$mfrow <- as.numeric(mfrow)
    }else{
      warning("mfrow: must be a numeric vector of two values")
    }
  }

  if (!is.null(dir)){
    if(length(options$mfrow)){
      polyGraph(res,options$mfrow,dir)
    }else{
      multiGraph(res,dir)
    }
  }

  return(structure(list(graphs = res, options = options),class="multi_rd3"))
}

# Evolving network
evolNetwork_rd3 <- function(..., frame = 0, speed = 50, loop = FALSE, lineplots = NULL, dir = NULL){
  net <- evolvingWrapper(list(...),frame,speed,loop,lineplots)
  if (!is.null(dir)) netCreate(net,dir)
  return(net)
}

# display multigraph with an index page
rd3_multiPages <- function(x, title = NULL, columns = NULL, imageSize = NULL, description = NULL, note = NULL, cex = 1, dir = tempDir(), show = FALSE){
  if(inherits(x,"multi_rd3")){
    multi <- x$graphs
    options <- list(names=names(multi))
    options$cex <- check_cex(cex)
    if(!is.null(title)){
      options$title <- title
    }
    images <- rep(NA,length(multi))
    descriptions <- rep(NA,length(multi))
    external <- rep(FALSE,length(multi))
    img2copy <- character()
    for(i in seq_along(multi)){
      if(is.list(multi[[i]])){
        if(is.character(multi[[i]]$description)){
          descriptions[[i]] <- multi[[i]]$description
        }
        if(is.character(multi[[i]]$image) && file.exists(multi[[i]]$image)){
          images[[i]] <- paste0("images/",basename(multi[[i]]$image))
          img2copy <- c(img2copy,multi[[i]]$image)
        }
      }
      if((is.character(multi[[i]]) && file.exists(paste0(multi[[i]],"/index.html"))) || inherits(multi[[i]],"evolMap")){
        external[[i]] <- TRUE
      }
    }
    if(!all(is.na(images))){
      options$images <- images
    }
    if(!all(is.na(descriptions))){
      options$descriptions <- descriptions
    }
    if(sum(external)){
      options$external <- external
    }
    if(!is.null(columns)){
      if(is.numeric(columns)){
        options$columns <- as.numeric(columns[1])
      }else{
        warning("columns: must be a numeric vector")
      }
    }
    if(!is.null(description)){
      options$description <- as.character(description)
    }
    if(!is.null(note)){
      options$note <- as.character(note)
    }
    if(!is.null(imageSize)){
      if(is.numeric(imageSize)){
        options$imgsize <- as.numeric(imageSize)
      }else{
        warning("imageSize: must be a numeric vector")
      }
    }
    createHTML(dir, c("bootstrap.scrolling.nav.css","multipages.css"), "multipages.js", toJSON(list(options=options)))
    dir.create(paste0(dir,"/pages"))
    for(n in names(multi)){
      if(is.character(multi[[n]])){
        if(file.exists(paste0(multi[[n]],"/index.html"))){
          file.copy(multi[[n]], paste0(dir,'/pages'), recursive = TRUE)
        }
      }else{
        multi[[n]]$options$multipages <- TRUE
        objCreate(multi[[n]],paste0(dir,"/pages/",n))
      }
    }
    if(length(img2copy)){
      dir.create(paste0(dir,"/images"))
      for(img in img2copy){
        file.copy(img,paste0(dir,"/images"))
      }
    }
    if(identical(show,TRUE)){
      browseURL(normalizePath(paste(dir, "index.html", sep = "/")))
    }else{
      message(paste0("The graph has been generated in the \"",normalizePath(dir),"\" path."))
    }
  }else{
    stop('x: not supported object.')
  }
}

rd3_addImage <- function(x,img){
  if(!is.character(img) || !file.exists(img)){
    stop('img: file not found.')
  }
  if(inherits(x,c("network_rd3","timeline_rd3","barplot_rd3","gallery_rd3","pie_rd3","evolMap"))){
    x$image <- img
    return(x)
  }else{
    stop('x: not supported object.')
  }
}

rd3_addDescription <- function(x,description){
  if(inherits(x,c("network_rd3","timeline_rd3","barplot_rd3","gallery_rd3","pie_rd3","evolMap"))){
    x$description <- as.character(description)
    return(x)
  }else{
    stop('x: not supported object.')
  }
}
