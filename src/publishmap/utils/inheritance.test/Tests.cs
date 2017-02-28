using System;
using System.Collections;
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
        public void merge_dictionaries()
        {
            var dict1 = new Dictionary<string, object>() {
                { "content", new Dictionary<string, string>() {
                    { "d1.content.prop1", "d1.content.val1" }
                } }
            };
            var content2 =
                new Dictionary<string, string>() {
                    { "newcontent.prop1", "newcontent.val1" }
                };

            Assert.True(((IDictionary)dict1["content"]).Contains("d1.content.prop1"));

            Inheritance.AddProperty(dict1, "content", content2, merge: true);

            Assert.True(dict1.ContainsKey("content"));

            Assert.True(((IDictionary)dict1["content"]).Contains("d1.content.prop1"));
            Assert.Equal("d1.content.val1", ((IDictionary)dict1["content"])["d1.content.prop1"]);

            Assert.True(((IDictionary)dict1["content"]).Contains("newcontent.prop1"));
            Assert.Equal("newcontent.val1", ((IDictionary)dict1["content"])["newcontent.prop1"]);
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
