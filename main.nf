#!/usr/bin/env nextflow

// default parameter values

params.predictionsFile = "$baseDir/TCGA_full_data/All_Together.txt"
params.public_ref_dir = "$baseDir/TCGA_full_data/public_ref"
params.participant_name = "my_gene_predictor"
params.metrics_ref_dir = "$baseDir/TCGA_full_data/metrics_ref_datasets"
params.cancer_types  = "ACC BRCA"
params.assess_dir = "$baseDir/TCGA_full_data/data"
params.results_dir = "out"

log.info """\
		   P I P E L I N E    
         =============================
         input file: ${params.predictionsFile}
         public reference directory : ${params.public_ref_dir}
         tool name : ${params.participant_name}
         metrics reference datasets: ${params.metrics_ref_dir}
		 selected cancer types: ${params.cancer_types}
		 benchmark data: ${params.assess_dir}
		 results directory: ${params.results_dir}
         """
.stripIndent()

// input files

input_file = file(params.predictionsFile)
ref_dir = Channel.fromPath( params.public_ref_dir, type: 'dir' )
tool_name = params.participant_name
gold_standards_dir = Channel.fromPath(params.metrics_ref_dir, type: 'dir' ) 
cancer_types = params.cancer_types
benchmark_data = Channel.fromPath(params.assess_dir, type: 'dir' )

// output 

result = file(params.results_dir)

process validation {

	input:
	file input_file
	file ref_dir 

	"""
	python /app/validation.py -i $input_file -r $ref_dir
	"""

}

process compute_metrics {

	input:
	file input_file
	val cancer_types
	file gold_standards_dir
	val tool_name
	val result

	output:
	val result into PARTICIPANT_DATA

	"""
	python /app/compute_metrics.py -i $input_file -c $cancer_types -m $gold_standards_dir -p $tool_name -o $result
	"""

}

process manage_assessment_data {

	input:
	file benchmark_data
	file output from PARTICIPANT_DATA

	"""
	python /app/manage_assessment_data.py -b $benchmark_data -p $output -o $output
	"""

}


workflow.onComplete { 
	println ( workflow.success ? "Done!" : "Oops .. something went wrong" )
}