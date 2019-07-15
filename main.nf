#!/usr/bin/env nextflow

if (params.help) {
	
	    log.info"""
	    ==============================================
	    TCGA CANCER DRIVER GENES BENCHMARKING PIPELINE 
	    ==============================================
	    Usage:
	    Run the pipeline with default parameters:
	    nextflow run main.nf

	    Run with user parameters:
 	    nextflow run main.nf --predictionsFile {driver.genes.file} --public_ref_dir {validation.reference.file} --participant_name {tool.name} --metrics_ref_dir {gold.standards.dir} --cancer_types {analyzed.cancer.types} --assess_dir {benchmark.data.dir} --results_dir {output.dir}

	    Mandatory arguments:
                --predictionsFile		List of cancer genes prediction
				--community_id			Name or OEB permanent ID for the benchmarking community
                --public_ref_dir 		Directory with list of cancer genes used to validate the predictions
                --participant_name  		Name of the tool used for prediction
                --metrics_ref_dir 		Dir that contains metrics reference datasets for all cancer types
                --challenges_ids  		List of types of cancer selected by the user, separated by spaces
                --assess_dir			Dir where the data for the benchmark are stored

	    Other options:
                --validation_result		The output directory where the results from validation step will be saved
				--assessment_results	The output directory where the results from the computed metrics step will be saved
				--outdir	The output directory where the consolidation of the benchmark will be saved
				--statsdir	The output directory with nextflow statistics
				--data_model_export_dir	The output dir where json file with benchmarking data model contents will be saved
	  			--otherdir					The output directory where custom results will be saved (no directory inside)
	    Flags:
                --help			Display this message
	    """.stripIndent()

	exit 1
} else {

	log.info """\
		 ==============================================
	     TCGA CANCER DRIVER GENES BENCHMARKING PIPELINE 
	     ==============================================
         input file: ${params.predictionsFile}
		 benchmarking community = ${params.community_id}
         public reference directory : ${params.public_ref_dir}
         tool name : ${params.participant_name}
         metrics reference datasets: ${params.metrics_ref_dir}
		 selected cancer types: ${params.challenges_ids}
		 benchmark data: ${params.assess_dir}
		 validation results directory: ${params.validation_result}
		 assessment results directory: ${params.assessment_results}
		 consolidated benchmark results directory: ${params.outdir}
		 Statistics results about nextflow run: ${params.statsdir}
		 Benchmarking data model file location: ${params.data_model_export_dir}
		 Directory with community-specific results: ${params.otherdir}
         """
	.stripIndent()

}


// input files

input_file = file(params.predictionsFile)
ref_dir = Channel.fromPath( params.public_ref_dir, type: 'dir' )
tool_name = params.participant_name.replaceAll("\\s","_")
gold_standards_dir = Channel.fromPath(params.metrics_ref_dir, type: 'dir' ) 
cancer_types = params.challenges_ids
benchmark_data = Channel.fromPath(params.assess_dir, type: 'dir' )
community_id = params.community_id

// output 
validation_out = file(params.validation_result)
assessment_out = file(params.assessment_results)
aggregation_dir = file(params.outdir)
data_model_export_dir = file(params.data_model_export_dir)
other_dir = file(params.otherdir)



/*
* Assuring the preconditions (in this case, the docker images) are in place
*/
process dockerPreconditions {

  tag "Building required docker images "
  publishDir path: "${params.statsdir}", mode: 'copy', overwrite: true

  output:
  file docker_image_dependency

  """
  docker build -t tcga_validation:1.0 "$baseDir/containers/tcga_validation" &&
  docker build -t tcga_metrics:1.0 "$baseDir/containers/tcga_metrics" &&
  docker build -t tcga_consolidation:1.0 "$baseDir/containers/tcga_consolidation" &&

  touch docker_image_dependency
  """

}

process validation {

	// validExitStatus 0,1
	tag "Validating input file format"

	input:
	file docker_image_dependency
	file input_file
	file ref_dir 
	val cancer_types
	val tool_name
	val community_id
	val validation_out

	output:
	val task.exitStatus into EXIT_STAT
	
	"""
	python /app/validation.py -i $input_file -r $ref_dir -com $community_id -c $cancer_types -p $tool_name -o $validation_out
	"""

}

process compute_metrics {

	tag "Computing benchmark metrics for submitted data"

	input:
	val file_validated from EXIT_STAT
	file input_file
	val cancer_types
	file gold_standards_dir
	val tool_name
	val community_id
	val assessment_out

	when:
	file_validated == 0

	output:
	val assessment_out into PARTICIPANT_DATA

	"""
	python /app/compute_metrics.py -i $input_file -c $cancer_types -m $gold_standards_dir -p $tool_name -com $community_id -o $assessment_out
	"""

}

process benchmark_consolidation {

	tag "Performing benchmark assessment and building plots"

	input:
	file benchmark_data
	file participant_metrics from PARTICIPANT_DATA
	val aggregation_dir
	file validation_out
	val data_model_export_dir

	"""
	python /app/manage_assessment_data.py -b $benchmark_data -p $participant_metrics -o $aggregation_dir
	python /app/merge_data_model_files.py -p $validation_out -m $participant_metrics -a $aggregation_dir -o $data_model_export_dir
	"""

}


workflow.onComplete { 
	println ( workflow.success ? "Done!" : "Oops .. something went wrong" )
}
