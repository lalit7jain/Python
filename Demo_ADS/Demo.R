#https://www.kaggle.com/msjgriffiths/d/benhamner/nips-2015-papers/nips-author-affiliations
library(dplyr)
library(tidyr)
library(readr)
library(ggplot2)
library(httr)
library(rvest)
library(stringr)
  
# Useful libraries
library(igraph)
library(devtools)
install_github("proxy")
#library(proxy)

# Pretty-printing
library(DT)
library(formattable)

authors <- read.csv("release-2016-02-29-02-26-09/output/Authors.csv")
paperauthors <- read_csv("release-2016-02-29-02-26-09/output/PaperAuthors.csv")
papers <- read_csv("release-2016-02-29-02-26-09/output/Papers.csv")


## Double check the count of the papers with the actual page by scrapping

url = "release-2016-02-29-02-26-09/output/accepted_papers.html"
page <- read_html(url)


# count papers

page %>% html_nodes(xpath = './/*[contains(@id, "main")]//i') -> nips.page.papers

data.frame(`KagglePapers` = nrow(papers),
           `AcceptedPapers` = length(nips.page.papers)) %>%
  mutate(`Equal` = `KagglePapers` == `AcceptedPapers`) %>%
  formattable(list(
    Equal = formatter("span", 
                      style = x ~ style(color = ifelse(x, "green", "red")),
                      x ~ icontext(ifelse(x, "ok", "remove"), ifelse(x, "Yes", "No")))
  ), 
  align = "l")


## Getting page headers from above which are in 

page %>%
  html_nodes(xpath = './/*[contains(@id, "main")]//b') %>%
  html_text() -> 
  page_authors

cat(head(page_authors))


## lets clean the page_authors
page_authors %>%
  str_split(";") %>% unlist %>% str_split(",",2) %>% unlist %>% trimws %>% 
    str_replace("\\*","") %>% 
      matrix(ncol=2, byrow = T,dimnames = list(NULL,c("Name","Institution"))) %>%
        as.data.frame -> authors_instituions

head(authors_instituions) %>% format_table(align = 'l')

## Does it match the Kaggle Authors

data.frame(
  KaggleAuthors = nrow(authors),
  AcceptedPapers = nrow(authors_instituions)
) %>%
  mutate(Equal = KaggleAuthors == AcceptedPapers) %>%
  formattable(list(
    Equal = formatter("span", 
                      style = x ~ style(color = ifelse(x, "green", "red")),
                      x ~ icontext(ifelse(x, "ok", "remove"), ifelse(x, "Yes", "No")))
  ), 
  align = "l")

## so it does not match. To learn more about who we’re missing, we need to match up the two tables.

  authors %>% left_join(authors_instituions) %>% 
    mutate(is_matched = !is.na(Institution)) %>%
    group_by(is_matched) %>%
    summarise(authors = n()) %>%
    formattable(list(authors = color_bar("orange")), align = 'l')

## 251 records are matching. We can drill down more
  
  authors_instituions %>%
    group_by(Name) %>%
    filter(n_distinct(Institution) > 1) %>% 
    arrange(Name) 

# It looks like:
#   
#   Some authors appear multiple times.
#   Some authors don’t have a listed affiliation.
# For the first case, we don’t want to keep duplicate information;
#  but in the second case, the fact than an author is either unaffiliated or unknown could be useful.  

## Removing duplicates   
  authors_instituions <- authors_instituions %>%  distinct
  
  
  authors_instituions %>%
    group_by(Name) %>%
    filter(n_distinct(Institution) > 1) %>% 
    arrange(Name)
  
# Moving on  
  authors %>% 
    left_join(authors_instituions) %>%
    mutate(is_matched = !is.na(Institution)) %>%
    group_by(is_matched) %>%
    summarise(count = n())
 
## checking which author did not match 
  authors_instituions %>% anti_join(authors) -> authors_failed_match
  nrow(authors_failed_match)
  head(authors_failed_match)
  
## Approximate name matching technique using Levenshtein distance!

## Trying to guess failed matches with the original matches
  failed_names <- as.character(authors_failed_match$Name) %>% trimws
  to_match_names <- authors %>% anti_join(authors_instituions) %>% .[["Name"]] %>% trimws

  costs = list(insertions = 3, deletions = 1, substitutions = 2)
  fuzzy_match <- adist(to_match_names, failed_names, costs = costs, ignore.case = T)
  match_cost <- apply(fuzzy_match, 1, min)
  data.frame(
    ToMatch = to_match_names, 
    Failed_Match = failed_names[apply(fuzzy_match, 1, which.min)], 
    Cost = match_cost) %>% 
    arrange(Cost) -> 
    approximate_matches

## APproximately same
approximate_matches %>% head(15)
  
## Matches with a cost of below 7 looks the same
correct_matches <- approximate_matches %>%
  filter(Cost <= 7, !(ToMatch %in% c("Andres Munoz", "David Schlegel")) )
dim(correct_matches)

# Define coalesce from SQL
coalesce <- function(x, y){ifelse(is.na(x), y, x)}


authors %>%
  left_join(correct_matches, by = c("Name" = "ToMatch")) %>%
  mutate(MatchKey = coalesce(as.character(Failed_Match), Name)) %>%
  left_join(authors_instituions, by = c("MatchKey" = "Name")) %>%
  select(-Failed_Match, -Cost, -MatchKey) ->
  authors_with_affiliations

head(authors_with_affiliations)

## Counting the number of authors per institution
authors_with_affiliations %>%
  group_by(Institution) %>%
  summarise(Authors = n()) %>%
  arrange(desc(Authors)) %>%
  head(20) %>%
  formattable(list(Authors = color_bar("orange")), align = 'l')
# 
# However: notice we have Google Deepmind in at #10. That’s interesting. Why are they separate?
# 
# We also have Stanford in at #19 - that should really roll up to Stanford.
# 
#    
# Recode the blank / null value
# Do some cleanup of the Institution name.

authors_with_affiliations %>%
  mutate(Institution = as.character(Institution),
         Institution = ifelse(Institution == "", NA, Institution)
  ) ->
  authors_with_affiliations

###
institution_cleanup <- data.frame(
  before = c('Stanford University', 'Carnegie Mellon University', 'Princeton University', 'Google DeepMind', 'Microsoft Research', 'University of Texas at Austin', 'New York University', 'Harvard University', 'Google, Inc.', 'Facebook AI research', 'University of Cambridge', 'stanford.edu', 'IBM Research-Almaden', 'Microsoft Research, Redmond, WA', 'IBM Research', 'University of Oxford', 'Duke', 'Massachusetts Institute of Technology', 'U. Montreal', 'Yahoo Labs', 'Adobe Research', '"University of Washington, Seattle"', 'UTexas-Austin', 'Columbia', 'INRIA - ENS', 'INRIA Lille - Nord Europe', 'University of Texas at Dallas', 'Gatsby unit, UCL', 'Cornell', 'UniversitÃ© de MontrÃ©al', 'Google Research', 'McGill University, Montreal', 'Chalmers University, Sweden', 'Microsoft Research Asia', 'Microsoft Research India', 'Washington University in STL', 'Â ', 'MIT Lincoln Laboratory', 'U. Toronto', 'Nokia Labs', 'University of Illinois at Chic', 'University of Illinois, Urbana-Champaign', 'University of Michigan-Ann Arbor', 'Xerox Research Centre Europe', 'UT Dallas', 'Microsoft Research, Redmond, W', 'UMich', 'MSR', 'MSR-INRIA', 'Ã‰cole Polytechnique MontrÃ©al', 'UniversitÃ© de Saint-Etienne', 'DeepMind', 'University of California, San Diego', 'Disney Research Pittsburgh', 'INRIA/ENS', '"University of Technology, Sydney"', 'Dr.', 'neuroscience', 'Google Inc.', 'Institut Mines-TÃ©lÃ©com, TÃ©lÃ©com ParisTech, CNRS LTCI', 'CIN, University TÃ¼bingen', 'MIT Mathematics', 'IBM Research, Ireland', 'Washington University in St Lo', 'Oxford University', 'Universit? de Montr?al', 'Parietal Team, INRIA', 'UniversitÃ© Pierre et Marie Curie (UPMC)', 'Polytechnique MontrÃ©al', 'Duke Univiersity', 'University of California, Davi', 'Google Inc', 'Princeton Neuroscience Inst.', 'Princeton Neuroscience Institute', '"""University of Washington, Seattle"""', 'google.com', 'University of Minnesota -- Twin Cities', 'Chalmers University of Technology, GÃ¶teborg', 'Microsoft.com', 'RENSSELAER POLYTECHNIC INST', 'University of Tech., Sydney', 'Rensselaer Polytechnic Inst.', 'Royal Holloway, Univ of London', 'University of Wisconsin, Madison', 'University Washington', 'Rugters University', 'UTDallas', 'Rutgers University', 'UW, Madison', 'Washington', 'Saarlanduniversity', 'MPI T?bingen', 'Samsung Research', 'Georgia Institute of Technolog', 'IIT-MIT', 'Shell Intl. E&P Inc.', 'Georgia Tech.', 'Simons Center for Data Analysi', 'Marburguniversity', 'Uni', 'Universit de MontrÃ©al', 'Mass. Institute of Technology', 'Adobe Research & INRIA', 'UniversitÃ© Paris Dauphine', 'Athens University of Economics and Business', 'Universite de Montreal', 'Stanford University & NVIDIA', 'University Collage London', 'Courant Institute and Google', 'University of California, Davis', 'Johnshopkins', 'TÃ©lÃ©com ParisTech', 'University of Columbia', 'CRIPAC, CASIA', 'IBM Thomas J. Watson Research Center', 'University of McGill', 'University of Michigan Ann Arb', 'Microsoft Research New York', 'Yale', 'UNIVERSITY OF MINNESOTA, TC', 'CMLA, ENS Cachan', 'The University of New South Wales', 'The University of Sheffield', 'University of TÃ¼bingen', 'Coloradoschoolofmines', 'Harvard Unviersity', 'Ttic', 'MIT CSAIL', 'University of Wisconsin - Madison', 'University of Wisconsin-Madiso', 'Cambridge University', 'U C Berkeley', 'U Texas', 'Utaustin', 'U. Amsterdam', 'MPI for Intelligent Systems', 'U. Michigan', 'UW Madison', 'UW-Madison', 'MPI Informatics', 'Washington Univ. in St. Louis', 'UC Berkeley / Google', 'MPI TÃ¼bingen', 'LPS, Ã‰cole Normale SupÃ©rieure', 'The Ohio State University', 'Yahoo!', 'The Pennsylvania State University', 'CMU', 'Facebook AI Research'),
  after = c('Stanford', 'Carnegie Mellon', 'Princeton', 'Google', 'Microsoft', 'University of Texas', 'NYU', 'Harvard', 'Google', 'Facebook', 'Cambridge', 'Stanford', 'IBM', 'Microsoft', 'IBM', 'Oxford', 'Duke University', 'MIT', 'University of Montreal', 'Yahoo', 'Adobe', 'University of Washington', 'University of Texas', 'Columbia University', 'INRIA', 'INRIA', 'University of Texas', 'University College London', 'Cornell University', 'University of Montreal', 'Google', 'McGill University', 'Chalmers University', 'Microsoft', 'Microsoft', 'Washington University in St. Louis', '', 'MIT', 'University of Toronto', 'Nokia', 'University of Illinois', 'University of Illinois', 'University of Michigan', 'Xerox', 'University of Texas', 'Microsoft', 'University of Michigan', 'Microsoft', 'Microsoft', 'Ecole Polytechnique Montreal', 'University de Saint-Etienne', 'Google', 'UC San Diego', 'Disney', 'INRIA', 'UT Sydney', 'UC Santa Barbara', 'Cambridge', 'Google', 'Telecom ParisTech', 'CIN', 'MIT', 'IBM', 'Washington University in St. Louis', 'Oxford', 'University of Montreal', 'INRIA', 'UPMC', 'Polytechnique Montreal', 'Duke University', 'UC Davis', 'Google', 'Princeton', 'Princeton', 'University of Washington', 'Google', 'University of Minnesota', 'Chalmers University', 'Microsoft', 'Rensselaer', 'UT Sydney', 'Rensselaer', 'University of London', 'University of Wisconsin-Madison', 'University of Washington', 'Rutgers', 'University of Texas', 'Rutgers', 'University of Wisconsin-Madison', 'University of Washington', 'Saarland University', 'Caltech', 'Samsung', 'Georgia Institute of Technology', 'MIT', 'Shell', 'Georgia Tech', 'Simons Foundation', 'Marburg University', 'University of Michigan', 'University of Montreal', 'MIT', 'Adobe', 'University Paris Dauphine', 'Athens University', 'University of Montreal', 'Stanford', 'University College London', 'Google', 'UC Davis', 'Johns Hopkins University', 'Telecom Paristech', 'Columbia University', 'CRIPAC', 'IBM', 'McGill University', 'University of Michigan', 'Microsoft', 'Yale University', 'University of Minnesota', 'CMLA', 'University of New South Wales', 'University of Sheffield', 'University of Tubingen', 'Colorado School of Mines', 'Harvard', 'Toyota Technological Institute at Chicago', 'MIT', 'University of Wisconsin-Madison', 'University of Wisconsin-Madison', 'Cambridge', 'UC Berkeley', 'University of Texas', 'University of Texas', 'University of Amsterdam', 'MPI', 'University of Michigan', 'University of Wisconsin-Madison', 'University of Wisconsin-Madison', 'MPI', 'Washington University in St. Louis', 'UC Berkeley', 'MPI', 'LPS', 'Ohio State University', 'Yahoo', 'University of Pennsylvania', 'Carnegie Mellon', 'Facebook'),
  stringsAsFactors = F
)

authors_with_affiliations %>%
  left_join(institution_cleanup, by = c("Institution" = "before")) %>%
  mutate(Institution = coalesce(after, Institution)) %>%
  select(-after) %>%
  distinct ->
  authors.affiliations


authors.affiliations %>%
  group_by(Institution) %>%
  summarise(Authors = n()) %>%
  arrange(desc(Authors)) %>%
  head(15) %>%
  formattable(list(Authors = color_bar("orange")), align = 'l')

## Exploring private paper's

private.companies <- c('Google', 'Microsoft', 'IBM', 'Facebook', 'Yahoo', 'Baidu', 'Adobe', 'SenseTime Group Limited', 'Gracenote', 'Xerox', 'Nokia', 'NVIDIA', 'Disney', 'Samsung', 'Shell', 'ZenRobotics', 'Epic Systems', 'Expedia, Geneva')
# 
# Given that, we can ask questions like:
#   
# How many authors were there from for-profile companies?
# How many papers did they publish?
# Did private companies collaborate on papers?
# Did they collaborate with academic institutions on those papers?

# 1) How many authors were there from for-profile companies?

authors.affiliations %>%
  filter(Institution %in% private.companies) %>%
  group_by(Institution) %>%
  summarise(Authors = n()) %>%
  arrange(desc(Authors)) %>% 
  formattable(list(Authors = color_bar("orange")), align = 'l')

# 2) How many papers did they publish?

authors.affiliations %>%
  filter(Institution %in% private.companies) %>%
  left_join(paperauthors, by = c("Id" = "AuthorId")) %>%
  group_by(Institution) %>%
  summarise(Papers = n_distinct(PaperId), 
            Authors = n_distinct(Id)) %>%
  arrange(desc(Papers)) %>%
  formattable(list(Papers = color_bar("orange")), align = 'l')

# Looking at it like that is a very different story!
#   
# Microsoft has nearly the same number of papers, but way fewer authors.
# 
# It’s also interesting to see that Facebook - which has a very respectable AI lab run by Yann LeCunn - submitted the same number of papers as Adobe and Yahoo, which I don’t tend to think of in the same breath.
# 
# Certainly, quantity of papers is not nearly as important as how influential those papers are; but perhaps it provides some scope about the volume of work being done.

# 3) Did private companies collaborate on papers?

authors.affiliations %>% 
  filter(Institution %in% private.companies) %>%
  left_join(paperauthors, by = c("Id" = "AuthorId")) %>%
  select(PaperId, Institution) ->
  private.papers

private.papers %>%
  group_by(PaperId) %>%
  summarise(Count = n_distinct(Institution)) %>%
  filter(Count > 1) %>%
  left_join(private.papers) %>%
  select(-Count) %>% 
  left_join(papers, by = c("PaperId" = "Id")) %>%
  group_by(Title) %>%
  arrange(Institution) %>%
  summarise(Institutions = toString(Institution))

# The interesting one is papers #2 - Google, Microsoft, and Samsung worked on a paper together?

# 4) Did they collaborate with academic institutions on those papers?

# a) Did authors work across institutions for most papers?

papers %>% 
  left_join(paperauthors, by = c("Id" = "PaperId")) %>%
  left_join(authors.affiliations, by = c("AuthorId" = "Id")) -> 
  papers.details

papers.details %>%
  group_by(Id) %>%
  summarise(Institutions = n_distinct(Institution)) %>%
  group_by(Institutions) %>%
  summarise(Papers = n()) %>%
  formattable(list(Papers = color_bar("orange")), align = 'l')

# This shows how many instituions collabarated on papers
## Checking papers in which 5 institutions collabrated

papers.details %>%
  group_by(Id) %>%
  summarise(Institutions = n_distinct(Institution)) %>%
  filter(Institutions == 5) %>% 
  left_join(papers.details) %>%
  group_by(Title) %>%
  summarise(Institutions = toString(Institution))

#########
######     Visualizing the Institutions
#########
# 
# Now that we have authors, institutions, and papers, we can think about this as a social network 
# 
# Institutions are nodes, and co-author status denotes an edge.
#  
# First, I’m going to construct an adjacency matrix that describes how many papers exist as edges.
# 
# I’m going to create a crosstab with papers by institution, and then define a distance function

papers.details %>%
  xtabs( ~ Institution + Id , data = .) -> 
  inst.links
inst.links[inst.links > 0] <- 1 

library(proxy)
adj.distance <- function(x, y) {sum(x * y)}
pr_DB$set_entry(FUN = adj.distance, names = c("adj.distance"))

adj.matrix <- dist(inst.links, "adj.distance")


library(igraph)
graph <- graph_from_adjacency_matrix(adj.matrix)


## Visualing only for Private companies

for.profit <- as.matrix(adj.matrix)
for.profit <- for.profit[rownames(for.profit) %in% private.companies,]
for.profit <- for.profit[,colSums(for.profit > 0)]

keep <- unique(c(rownames(for.profit),colnames(for.profit)))

keep.adj.matrix <- as.matrix(adj.matrix)[names(adj.matrix) %in% keep, names(adj.matrix) %in% keep]

graph <- graph_from_adjacency_matrix(keep.adj.matrix, mode = "undirected", weighted = T)
plot(graph)




papers.details %>%
  filter(Institution %in% names(V(graph))) %>%
  group_by(Institution) %>%
  summarise(Papers = n_distinct(Id)) %>%
  arrange(Institution) ->
  institution.paper.counts

# Set the volume to be propotional to the paper count
V(graph)$Papers = institution.paper.counts$Papers

# Set attribute for node colors
colrs = adjustcolor(c("grey40", "blue"))
V(graph)$Color = colrs[1 + (names(V(graph)) %in% private.companies)]


## iGraph plot
l <- layout.fruchterman.reingold(graph)
plot(graph, 
     #vertex.size = V(graph)$Papers, 
     vertex.color = V(graph)$Color,
     vertex.shape = "none",
     vertex.label.cex = log10(V(graph)$Papers),
     vertex.label.color = V(graph)$Color,
     edge.width=2,
     rescale = T,
     layout = l,
     asp = 0
)

#D3 Force Network
library(networkD3)
edges = as_edgelist(graph)
nodes = data.frame(Name = names(V(graph)), 
                   Size = V(graph)$Papers,
                   Group = c("Public", "Private")[1 + (names(V(graph)) %in% private.companies)])
nodes <- mutate(nodes, ID = 1:nrow(nodes) - 1)


edges %>% 
  as.data.frame %>%
  mutate(from = match(V1, nodes$Name) - 1,
         to = match(V2, nodes$Name) - 1) %>%
  select(-V1, -V2) -> 
  d3.edges

forceNetwork(d3.edges, nodes, "from", "to",
             NodeID = "Name", Nodesize = "Size", Group = "Group", 
             linkWidth = 1, linkColour = "#afafaf", fontSize=12, 
             zoom=T, legend=T, charge = -150, opacityNoHover = 0.2,
             radiusCalculation = "Math.sqrt(d.nodesize*2)+6", bounded = T)
