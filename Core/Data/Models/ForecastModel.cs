namespace WF.DataAccess.Models
{
    using Common.Entities;
    using System;
    using System.Data.Common;
    using System.Data.Entity;
    using System.Data.Entity.Infrastructure;

    public partial class ForecastModel : DbContext
    {
        public ForecastModel(DbConnection sqlconnection) : base(sqlconnection, false)
        {
            this.Configuration.LazyLoadingEnabled = false;
        }

           public virtual DbSet<Forecast> Forecasts { get; set; }
    }
}
