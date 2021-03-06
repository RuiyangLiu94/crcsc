# Normalize all public datasets using fRMA and store data in Synapse 
# 
# Author: Andreas Schlicker
###############################################################################

library(synapseClient)
library(rGithubClient)
library(frma)
library(stringr)
library(affy)

# GitHib repository
crcRepo = getRepo("andreas-schlicker/crcsc")
thisScript = getPermlink(crcRepo, "groups/F/normalization/frma_publicdata.r")

synapseLogin()

# Folder with all public datasets
pubFolder = "syn2176663"

# Get result files
allData = synapseQuery(paste('SELECT id, name FROM entity WHERE parentId=="', pubFolder, '"', sep=""))
# Remove possible confidence files
allData = allData[str_detect(allData[, "entity.name"], "GSE"), ]

for (i in 1:nrow(allData)) {
	# Get the files 
	files = synapseQuery(paste('SELECT id, name FROM entity WHERE parentId=="', allData[i, 2], '"', sep=""))
	rawFile = which(str_detect(files[, 1], "RAW"))
	geoId = unlist(str_split(allData[i, 1], "_"))[1]
	celDir = file.path(geoId, "CEL")
	
	if (file.exists(geoId)) {
		# Extract all CEL files and normalize
		dir.create(celDir, recursive=TRUE)
		system(paste("tar xf ", geoId, "/", str_replace(files[rawFile, 1], "_allsamples", ""), " -C ", celDir, sep=""))
		es = frma(ReadAffy(celfile.path=celDir, compress=TRUE), summarize="robust_weighted_average")
		colnames(es) = gsub(".gz", "", colnames(es))
		unlink(celDir, recursive=TRUE)
		
		# Write temporary file with expression data
		filePath = file.path(tempdir(), paste(geoId, "_frma_expression.tsv", sep=""))
		write.table(exprs(es), file=filePath, sep="\t", quote=FALSE)
		
		# List with used resources
		resources = list(list(entity=files[rawFile, 2], wasExecuted=F),
						list(url=thisScript, name=basename(thisScript), wasExecuted=T))
				
		# Store results in synapse and forget about the temporary file 
		synFile = File(path=filePath, parentId=allData[i, 2])
		failed = TRUE
		tries = 0
		while (failed && (tries < 5)) {
			res = tryCatch(synStore(synFile, used=resources),
						   error=function(e) NA)
			if (!is.na(res)) {
				failed=FALSE
			}
			tries = tries + 1
		}
		unlink(filePath)
	}
}

synapseLogout()
