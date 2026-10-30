#! /usr/bin/bash

#SBATCH --partition=cpu-single
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --time=08:00:00
#SBATCH --mem=64gb

module load math/R
module load devel/miniforge

conda activate r_env

Rscript SEHTestACS4_geometries.R
