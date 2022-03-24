# Peptide MD with Gromacs

Framework to run a mixed solvent molecular dynamics simulation with multiple
copies of a short peptide and various cosolvents.

## Usage

1. Copy `sequence-example.txt` to `sequence.txt` and put your sequence inside
2. Copy `env-example.sh` to `env.sh` and edit as needed
3. Type `make` to run simulation
4. Analyze `md_out.*` files

## Requirements

* gromacs
* pymol

## License

MIT License - Copyright (c) 2022 Thomas Holder
