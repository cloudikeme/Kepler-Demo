#!/bin/bash

# Define arrays of values for MAX_CONCURRENCY and NUM_PROMPT
max_concurrency_values=(1 2 4 8 16)
num_prompt_values=(100 100 100 100 100)
sm_levels=("540" "810" "1110" "1410")

# Adjust if you have multiple GPUs and want to set them differently
gpu_index=1

# Loop through the arrays of SM_LEVELS
for sm in "${sm_levels[@]}"; do
  # Set the GPU frequency
  echo "Setting GPU $gpu_index frequency to $sm MHz"
  nvidia-smi -i $gpu_index -ac "1215,${sm}"

  # Create a directory for the current frequency
  result_dir="/data/benchmarking-results/sm_$sm"
  echo "Creating directory $result_dir for the results"
  mkdir -p "$result_dir"
  
  # Loop through the arrays
  for i in "${!max_concurrency_values[@]}"; do
    # Prepare the .env file from template.env without altering the original
    sed "s/\[max_concurrency\]/${max_concurrency_values[$i]}/g" template.env | \
    sed "s/\[num_prompt\]/${num_prompt_values[$i]}/g" > .env
    
    # Create the configmap
    kubectl create configmap vllm-benchmark-config --from-env-file=.env
    
    # Start the benchmarking job
    kubectl create -f loadtesting-job.yaml
    
    # Wait for the job to complete with a robust loop
    job_name=$(kubectl get jobs --selector=jobgroup=benchmarking -o jsonpath='{.items[*].metadata.name}')
    echo "Waiting for job $job_name to complete..."
    
    while : ; do
      job_status=$(kubectl get job $job_name -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}')
      if [ "$job_status" == "True" ]; then
        echo "Job $job_name completed."
	break
      else
	echo "Waiting for job completion..."
	sleep 10
      fi
    done
    
    # Delete the job
    echo "Deleting job $job_name..."
    kubectl delete job $job_name

    # Delete the configmap
    kubectl delete configmap vllm-benchmark-config

    # Rename the generated JSON files
    mv /data/benchmarking-results/ShareGPT_V3_unfiltered_cleaned_split.json $result_dir/output_concurrency${max_concurrency_values[$i]}_numprompt${num_prompt_values[$i]}.json

    # Find and rename the file with datetime in its name
    rst_file=$(ls /data/benchmarking-results/openai-chat*.json)
    mv "$rst_file" $result_dir/results_concurrency${max_concurrency_values[$i]}_numprompt${num_prompt_values[$i]}.json
  done

  echo "Benchmarking experiment completed for GPU frequency $sm !"
done
