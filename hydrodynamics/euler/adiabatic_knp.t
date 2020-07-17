/*
 * adiabatic_knp.t
 *
 *  Created on: 29 Apr 2020
 *  Author: Holger Schmitz (holger@notjustphysics.com)
 */

#include <schnek/tools/literature.hpp>

template<int rank>
inline double AdiabaticKnpModel<rank>::flow_speed(size_t direction, const FluidValues &u, const InternalVars &p)
{
  return u[C_M[direction]] / u[C_RHO];
}

template<int rank>
inline double AdiabaticKnpModel<rank>::sound_speed(const FluidValues &u, const InternalVars &p)
{
  return (p[0]>0.0)?(0.5*sqrt(4.0*adiabaticGamma*p/u[C_RHO])):0.0;
}

template<int rank>
inline void AdiabaticKnpModel<rank>::calc_internal_vars(const FluidValues &u, InternalVars &p)
{
  double sqrU = 0.0;
  for (size_t i=0; i<dim; ++i)
  {
    sqrU += u[C_M[i]]*u[C_M[i]];
  }

  double internal_energy = std::max(0.0, u[C_E] - 0.5*sqrU/u[C_RHO]);

  p[0] = (adiabaticGamma-1.0)*internal_energy;
}

template<int rank>
void AdiabaticKnpModel<rank>::flux_function(size_t direction,
                                            const FluidValues &u,
                                            const InternalVars &p,
                                            FluidValues &f)
{
  double rho = u[C_RHO];
  double mdir = u[C_M[direction]];
  double engy = u[C_E];

  f[C_RHO]   = mdir;
  f[C_E]     = (engy + p[0])*mdir/rho;
  for (size_t i=0; i<dim; ++i)
  {
    f[C_M[i]] = mdir*u[C_M[i]]/rho;
  }
  f[C_M[direction]] += p[0];

}

template<int rank>
void AdiabaticKnp<rank>::initParameters(schnek::BlockParameters &parameters)
{
  parameters.addParameter("gamma", &adiabaticGamma, 1.4);
}

template<int rank>
void AdiabaticKnp<rank>::init()
{
  Super::init();

  retrieveData("Rho", Rho);
  scheme.setField(C_RHO, *Rho);
  integrator.setField(C_RHO, *Rho);
  boundary.setField(C_RHO, *Rho);

  retrieveData("E", E);
  scheme.setField(C_E, *E);
  integrator.setField(C_E, *E);
  boundary.setField(C_E, *E);


  for (size_t i=0; i<DIMENSION; ++i)
  {
    retrieveData(indexToCoord(i, "M"), M[i]);
    scheme.setField(C_M[i], *M[i]);
    integrator.setField(C_M[i], *M[i]);
    boundary.setField(C_M[i], *M[i]);
  }

  auto boundaries = BlockContainer<BoundaryCondition<Field, rank>>::childBlocks();
  boundary.addBoundaries(boundaries.begin(), boundaries.end());


  schnek::LiteratureArticle Kurganov2001("Kurganov2001", "A. Kurganov and S. Noelle and G. Petrova",
      "Semidiscrete central-upwind schemes for hyperbolic conservation laws and Hamilton--Jacobi equations",
      "SIAM J. Sci. Comput.", "2001", "23", "707");

  schnek::LiteratureManager::instance().addReference(
      "Semidiscrete central-upwind scheme for hyperbolic conservation laws", Kurganov2001);
}

template<int rank>
double AdiabaticKnp<rank>::maxDt()
{
  schnek::DomainSubdivision<Field> &subdivision = getContext().getSubdivision();

  Field &Rho = *(this->Rho);
  Field &E = *(this->E);
  schnek::Array<Field*, DIMENSION> M;
  for (size_t i=0; i<DIMENSION; ++i)
  {
    M[i] = &(*this->M[i]);
  }

  Index lo = Rho.getInnerLo();
  Index hi = Rho.getInnerHi();
  Range range(lo, hi);
  Range::iterator range_end = range.end();

  FluidValues u;
  double max_speed = 0.0;

  double min_dx = dx[0];

  for (size_t i=1; i<DIMENSION; i++)
  {
    min_dx = std::min(min_dx, dx[i]);
  }

  for (Range::iterator it = range.begin();
       it != range_end;
       ++it)
  {
    const Index &p = *it;
    u[C_RHO]    = Rho[p];

    double maxU = 0.0;
    for (size_t i=0; i<DIMENSION; ++i)
    {
      u[C_M[i]]    = (*M[i])[p];
      maxU = std::max(maxU, fabs(u[C_M[i]]));
    }
    u[C_E] = E[p];

    // TODO this won't work yet
    double pressure = eqn_state_ideal_gas(u);

    double v_max = maxU/u[C_RHO];

    max_speed = std::max(max_speed,speed_cf(u[C_RHO], pressure)+v_max);
  }

  max_speed = subdivision.maxReduce(max_speed);
  return min_dx/max_speed;
}

template<int rank>
void AdiabaticKnp<rank>::timeStep(double dt)
{
  integrator.integrateStep(dt, scheme, boundary);
}

