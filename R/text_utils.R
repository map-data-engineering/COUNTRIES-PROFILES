## ==========================================================================
##  R/text_utils.R
##  Text helpers shared by the generator and the figure/table scripts.
##
##  italicise_species(x)   puts scientific names in markdown italics:
##       Anopheles funestus, An. gambiae, Plasmodium falciparum, P. vivax,
##       and the genus words Anopheles / Plasmodium on their own.
##       Qualifiers (s.s., s.l.), authorities (Giles, 1902) and "et al." stay plain.
##       Links, HTML tags and text that is already italic are left alone.
##  To add a species, add its epithet to sp_epithets below. One list for all countries.
## ==========================================================================

sp_epithets <- c("funestus", "gambiae", "arabiensis", "coluzzii", "merus", "melas", "stephensi",
                 "nili", "moucheti", "pharoensis", "rivulorum", "leesoni", "parensis", "vaneedeni",
                 "coustani", "squamosus", "ziemanni", "culicifacies", "minimus", "dirus", "albimanus",
                 "sinensis", "maculatus", "darlingi", "labranchiae", "sergentii", "demeilloni", "longipalpis",
                 "falciparum", "vivax", "malariae", "ovale", "knowlesi")

italicise_species <- function(x) {
  ep  <- paste(sp_epithets, collapse = "|")
  pat_binomial <- paste0("(?<![A-Za-z0-9*_])(Anopheles|An\\.|Plasmodium|P\\.)\\s+(", ep, ")(?![A-Za-z*_])")
  pat_genus    <- "(?<![A-Za-z0-9*_])(Anopheles|Plasmodium)(?![A-Za-z*_])"
  prot_re <- "\\]\\([^)]*\\)|<[^>]*>|https?://[^\\s)\"'<]+"
  vapply(as.character(x), function(s) {
    if (is.na(s) || !nzchar(s)) return(s)
    prot <- regmatches(s, gregexpr(prot_re, s, perl = TRUE))[[1]]
    for (i in seq_along(prot)) s <- sub(prot[i], sprintf("\001%d\002", i), s, fixed = TRUE)
    s <- gsub(pat_binomial, "*\\1 \\2*", s, perl = TRUE)
    s <- gsub(pat_genus,    "*\\1*",     s, perl = TRUE)
    for (i in seq_along(prot)) s <- sub(sprintf("\001%d\002", i), prot[i], s, fixed = TRUE)
    s
  }, character(1), USE.NAMES = FALSE)
}
