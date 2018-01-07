using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace WF.Common.Entities.Enums
{
    //TODO:  Refactor to generate values using .tt from sql table
    //       Need the gen infrastructure in place, first
    public static class AccuracyInstinctEnum
    {
        public const int PrettyIffy = 1;
        public const int OnTheFence = 2;
        public const int HighAccuracy = 3;
    }
}
