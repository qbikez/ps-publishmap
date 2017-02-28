using System;
using System.Collections.Generic;
using System.Diagnostics;
using Xunit;

namespace Publishmap.Utils.Inheritance.Tests
{
    public class Tests
    {
        [Fact]
        public void add_property_to_empty_dict()
        {
            var dict1 = new Dictionary<string, string>();

            Inheritance.AddProperty(dict1, "prop1", "val1");

            Assert.Equal("val1", dict1["prop1"]);
        }

        [Fact]
        public void add_property_performance()
        {

            int count = 6000;
            var dict1 = new Dictionary<string, string>();

            var sw = Stopwatch.StartNew();
            for (var i = 0; i < count; i++)
            {
                  Inheritance.AddProperty(dict1, $"prop{i}", $"val{1}");
            }

            System.Console.WriteLine($"{count} iterations took {sw.ElapsedMilliseconds}ms");
        }
    }
}
