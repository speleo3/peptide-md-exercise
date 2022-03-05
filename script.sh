#!/bin/bash

set -xe

if [[ -e env.sh ]]; then
    source env.sh
fi

if [[ ! -e sequence.txt ]]; then
    echo "Please create sequence.txt"
    exit 1
fi

sequence=$(grep -v '^#' sequence.txt)

# Temporary files location
tmp=tmp
mkdir -p $tmp

# "Current pipeline file" library :-)
CURRENT_NUM_FILE=$tmp/current-num.txt
echo 0 > $CURRENT_NUM_FILE
curr() {
    read num < $CURRENT_NUM_FILE
    echo "$tmp/current-$num"
}
next() {
    read num < $CURRENT_NUM_FILE
    echo $((num+1)) > $CURRENT_NUM_FILE
    curr
}

get-amino-acid() {
    aa_lower=$(echo $1| tr '[:upper:]' '[:lower:]')
    aa_upper=$(echo $1| tr '[:lower:]' '[:upper:]')
pymol -ckq \
    -d "fetch $aa_upper" \
    -d "save ${aa_lower}_noh.pdb, not hydro"
    # Use ZWITTERION_* termini (failed with autoprompt.py?)
    gmx pdb2gmx -f ${aa_lower}_noh.pdb -o $aa_lower.gro -water spce -ff oplsaa -p topol-$aa_lower.top -ter <<EOF
1
1
EOF
    sed -n "s/^Protein /$aa_upper /;/moleculetype/,/Include Position restraint/p" topol-$aa_lower.top > $aa_lower.itp
}

# Make extended conformation
pymol -ckq \
    -d "fab $sequence, hydro=0, chain=A" \
    -d 'edit last name C' \
    -d 'attach O, 3, 1, OXT' \
    -d 'save pept_ext_noh.pdb'

# Make helix conformation
pymol -ckq \
    -d "fab $sequence, hydro=0, chain=A, ss=1" \
    -d 'edit last name C' \
    -d 'attach O, 3, 1, OXT' \
    -d 'save pept_hel_noh.pdb'

# Get amino acids
get-amino-acid ARG
get-amino-acid TYR

# Get DMSO
pymol -ckq \
    -d "fetch DMS" \
    -d "alter all, (resn,name)=('DMSO',name[0]+'D'+name[1:])" \
    -d 'save dmso_noh.pdb, not hydro'
gmx pdb2gmx -f dmso_noh.pdb     -o dmso.gro     -water spce -ff oplsaa -p topol-dmso.top
sed -n 's/^Other/DMSO /;/moleculetype/,/Include Position restraint/p' topol-dmso.top > dmso.itp

# Convert PDB to GRO and TOP
gmx pdb2gmx -f pept_hel_noh.pdb -o pept_hel.gro -water spce -ff oplsaa
gmx pdb2gmx -f pept_ext_noh.pdb -o pept_ext.gro -water spce -ff oplsaa

# Add box
gmx editconf -f pept_ext.gro -o $(next).gro -c -d 3.0 -bt dodecahedron

# Insert more peptide copies
gmx insert-molecules -f $(curr).gro -ci pept_ext.gro -nmol 1 -try 20 -o $(next).gro
gmx insert-molecules -f $(curr).gro -ci pept_hel.gro -nmol 2 -try 20 -o $(next).gro
n_pept=$(grep -c "HIS      N" $(curr).gro)
sed -i "/molecules/,\$s/^Protein_chain_A .*$/Protein_chain_A     $n_pept/" topol.top

# Insert DMSO molecules
if [[ ${NMOL_DMSO:-0} > 0 ]]; then
    gmx insert-molecules -f $(curr).gro -ci dmso.gro -nmol $NMOL_DMSO -try 20 -o $(next).gro
    sed -i '/^#include "oplsaa.ff.ions.itp"/a #include "dmso.itp"' topol.top
    n_dmso=$(grep -c "DMSO    SD" $(curr).gro)
    echo "DMSO             $n_dmso" >> topol.top
fi

# Insert arginine molecules
if [[ ${NMOL_ARG:-0} > 0 ]]; then
    gmx insert-molecules -f $(curr).gro -ci arg.gro -nmol $NMOL_ARG -try 20 -o $(next).gro
    sed -i '/^#include "oplsaa.ff.ions.itp"/a #include "arg.itp"' topol.top
    echo "ARG $NMOL_ARG" >> topol.top
fi

# Insert tyrosine molecules
if [[ ${NMOL_TYR:-0} > 0 ]]; then
    gmx insert-molecules -f $(curr).gro -ci tyr.gro -nmol $NMOL_TYR -try 20 -o $(next).gro
    sed -i '/^#include "oplsaa.ff.ions.itp"/a #include "tyr.itp"' topol.top
    echo "TYR $NMOL_TYR" >> topol.top
fi

# Insert Water molecules
gmx solvate -cp $(curr).gro -cs spc216.gro -o $(next).gro -p topol.top

# Ions to neutralize net charge
gmx grompp -f mdp/ions.mdp -c $(curr).gro -p topol.top -o $(next).tpr
python3 autoprompt.py \
    "gmx genion -s $(curr).tpr -o $(next).gro -p topol.top -pname NA -nname CL -neutral -conc ${CONC_NACL:-0}" \
    'Group *(\d+) \( *SOL\)'

# Energy minimization
gmx grompp -f mdp/minim.mdp -c $(curr).gro -p topol.top -o $(next).tpr
gmx mdrun -deffnm $(curr)

# Equilibration NVT: Constant volume and temperature
gmx grompp -f mdp/nvt.mdp -c $(curr).gro -r $(curr).gro -p topol.top -o $(next).tpr
gmx mdrun -deffnm $(curr)

# Equilibration NPT: Constant pressure and temperature
gmx grompp -f mdp/npt.mdp -c $(curr).gro -r $(curr).gro -t $(curr).cpt -p topol.top -o $(next).tpr
gmx mdrun -deffnm $(curr)

# For convenience. Such a file will also be created at the end of the MD.
cp $(curr).gro md_out.gro

# MD! :-)
gmx grompp -f mdp/md.mdp -c $(curr).gro -t $(curr).cpt -p topol.top -o md_out.tpr
gmx mdrun -deffnm md_out

# Unwrap periodic boundary box per molecule and reduce number of frames
# python3 autoprompt.py ... 'Group *(\d+) \( *System\)'
gmx trjconv -s md_out.tpr -f md_out.xtc -o md_out_noPBC.xtc -pbc mol -skip 4 <<< 0

# Visualize
# pymol md_out.gro -d 'load_traj md_out_noPBC.xtc'
