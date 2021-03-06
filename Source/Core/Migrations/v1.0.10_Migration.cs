﻿#region Copyright 2014 Exceptionless

// This program is free software: you can redistribute it and/or modify it 
// under the terms of the GNU Affero General Public License as published 
// by the Free Software Foundation, either version 3 of the License, or 
// (at your option) any later version.
// 
//     http://www.gnu.org/licenses/agpl-3.0.html

#endregion

using System;
using MongoDB.Bson;
using MongoDB.Driver;
using MongoMigrations;

namespace Exceptionless.Core.Migrations {
    public class RemoveOldClientInstallDateMigration : CollectionMigration {
        public RemoveOldClientInstallDateMigration()
            : base("1.0.10", ErrorRepository.CollectionName) {
            Description = "Remove non-DateTimeOffset old client install dates.";
        }

        public override void UpdateDocument(MongoCollection<BsonDocument> collection, BsonDocument document) {
            if (!document.Contains(ErrorRepository.FieldNames.ExceptionlessClientInfo))
                return;

            BsonDocument clientInfo = document.GetElement(ErrorRepository.FieldNames.ExceptionlessClientInfo).Value.AsBsonDocument;

            if (clientInfo.Contains("SubmissionMethod"))
                clientInfo.ChangeName("SubmissionMethod", ErrorRepository.FieldNames.SubmissionMethod);

            if (clientInfo.Contains(ErrorRepository.FieldNames.InstallDate)) {
                BsonValue installDateValue = clientInfo.GetElement(ErrorRepository.FieldNames.InstallDate).Value;
                if (installDateValue.IsBsonArray)
                    return;

                DateTime installDate = installDateValue.ToUniversalTime();
                clientInfo.AsBsonDocument.Set(ErrorRepository.FieldNames.InstallDate, new BsonArray(new BsonValue[] { new BsonInt64(installDate.Ticks), new BsonInt32(-360) }));
            }

            collection.Save(document);
        }
    }
}