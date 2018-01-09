using System;
using System.ComponentModel.DataAnnotations.Schema;
using WF.Common.Interfaces;

namespace WF.Common.Entities
{
    [Table("Forecast")]
    public partial class Forecast : IEntity
    {
        public int Id { get; set; }
        public int ForecastRegionId { get; set; }
        public int ForecastSourceId { get; set; }
        public Nullable<int> WeatherModelUsedId { get; set; }
        public System.DateTime ForecastMadeDate { get; set; }
        public System.DateTime ForecastRangeStartDate { get; set; }
        public System.DateTime ForecastRangeEndDate { get; set; }
        public string ForecasterComments { get; set; }
        public Nullable<int> AccuracyInstinctId { get; set; }
        public System.Guid GlobalId { get; set; }
        public System.DateTime Created { get; set; }
        public string CreatedBy { get; set; }
        public System.DateTime LastModified { get; set; }
        public string LastModifiedBy { get; set; }
    }
}
